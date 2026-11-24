import os, json, sqlite3, secrets, hashlib, hmac, re, time, base64, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from contextlib import closing

DB=os.getenv('CHAT_DB','chat.db'); INVITE=os.getenv('CHAT_INVITE',''); LIMIT=24*1024*1024

def db():
    c=sqlite3.connect(DB, timeout=15); c.row_factory=sqlite3.Row; c.execute('PRAGMA foreign_keys=ON'); c.create_function('casefold',1,lambda v: (v or '').casefold()); return c

def init():
    with closing(db()) as c, c:
        c.executescript('''
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, name TEXT NOT NULL, username TEXT UNIQUE COLLATE NOCASE, email TEXT UNIQUE COLLATE NOCASE NOT NULL, salt TEXT NOT NULL, hash TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, uid INTEGER REFERENCES users(id), expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS chats(id INTEGER PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL, owner INTEGER REFERENCES users(id), direct_key TEXT UNIQUE);
        CREATE TABLE IF NOT EXISTS members(chat INTEGER REFERENCES chats(id), uid INTEGER REFERENCES users(id), PRIMARY KEY(chat,uid));
        CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY, chat INTEGER REFERENCES chats(id), sender INTEGER REFERENCES users(id), kind TEXT NOT NULL, body TEXT NOT NULL, created INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS calls(id INTEGER PRIMARY KEY, chat INTEGER REFERENCES chats(id), caller INTEGER REFERENCES users(id), callee INTEGER REFERENCES users(id), video INTEGER NOT NULL, status TEXT NOT NULL, created INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS signals(id INTEGER PRIMARY KEY, call INTEGER REFERENCES calls(id), sender INTEGER REFERENCES users(id), payload TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS reactions(message INTEGER REFERENCES messages(id) ON DELETE CASCADE, uid INTEGER REFERENCES users(id), emoji TEXT NOT NULL, PRIMARY KEY(message,uid));
        CREATE TABLE IF NOT EXISTS read_marks(chat INTEGER REFERENCES chats(id), uid INTEGER REFERENCES users(id), last_id INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(chat,uid));
        CREATE TABLE IF NOT EXISTS pins(chat INTEGER PRIMARY KEY REFERENCES chats(id), message INTEGER REFERENCES messages(id) ON DELETE CASCADE);
        CREATE INDEX IF NOT EXISTS msg_chat_id ON messages(chat,id);
        ''')
        cols={r['name'] for r in c.execute('PRAGMA table_info(messages)')}
        for name, typ in [('edited','INTEGER'),('deleted','INTEGER NOT NULL DEFAULT 0'),('reply_to','INTEGER'),('filename','TEXT')]:
            if name not in cols: c.execute(f'ALTER TABLE messages ADD COLUMN {name} {typ}')

        ucols={r['name'] for r in c.execute('PRAGMA table_info(users)')}
        for name,typ in [('role',"TEXT NOT NULL DEFAULT 'member'"),('banned','INTEGER NOT NULL DEFAULT 0'),('bio',"TEXT NOT NULL DEFAULT ''")]:
            if name not in ucols: c.execute(f'ALTER TABLE users ADD COLUMN {name} {typ}')
        c.executescript("""
        CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY, actor INTEGER NOT NULL, action TEXT NOT NULL, target INTEGER, created INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS chat_prefs(uid INTEGER REFERENCES users(id),chat INTEGER REFERENCES chats(id),favorite INTEGER NOT NULL DEFAULT 0,archived INTEGER NOT NULL DEFAULT 0,muted INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(uid,chat));
        CREATE TABLE IF NOT EXISTS saved_messages(uid INTEGER REFERENCES users(id),message INTEGER REFERENCES messages(id),PRIMARY KEY(uid,message));
        CREATE TABLE IF NOT EXISTS blocks(uid INTEGER REFERENCES users(id),blocked INTEGER REFERENCES users(id),PRIMARY KEY(uid,blocked));
        CREATE TABLE IF NOT EXISTS reports(id INTEGER PRIMARY KEY,reporter INTEGER REFERENCES users(id),message INTEGER REFERENCES messages(id),reason TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'open',created INTEGER NOT NULL);
        CREATE UNIQUE INDEX IF NOT EXISTS single_owner ON users(role) WHERE role='owner';
        """)
        c.execute("INSERT OR IGNORE INTO settings VALUES('registration','open')")
        c.execute("INSERT OR IGNORE INTO settings VALUES('announcement','')")
        owner=c.execute("SELECT id FROM users WHERE role='owner'").fetchone()
        if not owner:
            p=os.getenv('TELEZEKA_OWNER_PASSWORD','')
            if len(p)<16 or len(p)>256: raise RuntimeError('Set TELEZEKA_OWNER_PASSWORD (16-256 characters) before first start')
            if c.execute("SELECT 1 FROM users WHERE username='zakaria' OR email='zakaria@telezeka.local'").fetchone():
                raise RuntimeError('Reserved owner name/email already exists; resolve manually before migration')
            salt=secrets.token_hex(16)
            uid=c.execute("INSERT INTO users(name,username,email,salt,hash,role) VALUES(?,?,?,?,?,'owner')",('Закария','zakaria','zakaria@telezeka.local',salt,password(p,salt))).lastrowid
            c.execute("INSERT INTO audit(actor,action,target,created) VALUES(?,?,?,?)",(uid,'owner_bootstrap',uid,int(time.time())))

def setting(c,key):
    return c.execute('SELECT value FROM settings WHERE key=?',(key,)).fetchone()[0]
def audit(c,actor,action,target=None):
    c.execute('INSERT INTO audit(actor,action,target,created) VALUES(?,?,?,?)',(actor,action,target,int(time.time())))
def blocked(c,a,b):
    return c.execute('SELECT 1 FROM blocks WHERE (uid=? AND blocked=?) OR (uid=? AND blocked=?)',(a,b,b,a)).fetchone()
def check_direct(c,u,room):
    if room['kind']=='direct':
        other=c.execute('SELECT uid FROM members WHERE chat=? AND uid!=?',(room['id'],u)).fetchone()
        need(other and not blocked(c,u,other['uid']),'Общение недоступно',403)
        need(not c.execute('SELECT banned FROM users WHERE id=?',(other['uid'],)).fetchone()['banned'],'Общение недоступно',403)

def message_rows(c,u,ch,where='',params=(),limit=200,descending=False):
    sql="""SELECT m.id,m.sender,m.kind,CASE WHEN m.kind='text' THEN m.body ELSE '' END AS body,m.created,users.name,m.edited,m.deleted,m.reply_to,m.filename,
      CASE WHEN r.deleted=1 THEN 'Сообщение удалено' WHEN r.kind='text' THEN substr(r.body,1,160) ELSE 'Вложение' END AS reply_preview
      FROM messages m JOIN users ON m.sender=users.id LEFT JOIN messages r ON r.id=m.reply_to AND r.chat=m.chat WHERE m.chat=? """
    rows=c.execute(sql+where+' ORDER BY m.id '+('DESC' if descending else 'ASC')+' LIMIT ?',(ch,*params,limit)).fetchall()
    out=[]
    for row in (reversed(rows) if descending else rows):
        a=dict(row)
        if a['deleted']: a.update(body='',filename=None,reply_preview=None,reply_to=None)
        a['reactions']=[dict(x) for x in c.execute('SELECT emoji,COUNT(*) AS count,MAX(uid=?) AS mine FROM reactions WHERE message=? GROUP BY emoji',(u,a['id']))] if not a['deleted'] else []
        out.append(a)
    return out

def password(p,s): return hashlib.scrypt(p.encode(),salt=bytes.fromhex(s),n=16384,r=8,p=1,dklen=32).hex()
def tokenhash(t): return hashlib.sha256(t.encode()).hexdigest()
def public(r): return {k:r[k] for k in ('id','name','username','role','bio')}
class Err(Exception):
    def __init__(self,status,msg): self.status=status; self.msg=msg

def need(ok,msg='Нет доступа',status=403):
    if not ok: raise Err(status,msg)
def clean(v,maxlen=80): return str(v or '').strip()[:maxlen]
def username(v):
    v=clean(v,40).lower().lstrip('@'); need(not v or re.fullmatch(r'[a-z0-9_]{3,32}',v),'Username: 3–32 латинских символа, цифры, _',400); return v or None

def member(c,u,ch):
    r=c.execute('SELECT chats.* FROM chats JOIN members ON chats.id=members.chat WHERE chats.id=? AND members.uid=?',(ch,u)).fetchone(); need(r); return r

def peer(c,un):
    r=c.execute('SELECT * FROM users WHERE username=?',(username(un),)).fetchone(); need(r,'Пользователь не найден',404); return r

def session(c,u):
    t=secrets.token_urlsafe(32); c.execute('INSERT INTO sessions VALUES(?,?,?)',(tokenhash(t),u,int(time.time())+30*86400)); return {'token':t,'user':public(c.execute('SELECT * FROM users WHERE id=?',(u,)).fetchone())}

def run(c,method,path,q,d,auth):
    now=int(time.time()); route=path.strip('/').split('/')
    if path=='/health': return {'ok':True}
    if method=='POST' and path in ('/register','/login'):
        e=clean(d.get('email'),254).lower(); p=str(d.get('password','')); need(3<=len(e) and '@' in e and 8<=len(p)<=256,'Проверьте email и пароль (от 8 символов)',400)
        if path=='/register':
            need(setting(c,'registration')=='open','Регистрация закрыта',403)
            need(e!='zakaria@telezeka.local' and username(d.get('username'))!='zakaria','Имя зарезервировано',409)
            need(bool(INVITE) and hmac.compare_digest(str(d.get('invite','')),INVITE),'Неверный код приглашения'); n=clean(d.get('name')); need(n,'Укажите имя',400); s=secrets.token_hex(16)
            u=c.execute('INSERT INTO users(name,username,email,salt,hash) VALUES(?,?,?,?,?)',(n,username(d.get('username')),e,s,password(p,s))).lastrowid
        else:
            r=c.execute('SELECT * FROM users WHERE email=?',(e,)).fetchone(); actual=password(p,r['salt'] if r else '0'*32); need(r and hmac.compare_digest(actual,r['hash']),'Неверный email или пароль',401); need(not r['banned'],'Аккаунт заблокирован',403); u=r['id']
        return session(c,u)
    t=auth.removeprefix('Bearer '); r=c.execute('SELECT sessions.uid,users.role FROM sessions JOIN users ON sessions.uid=users.id WHERE token=? AND expires>? AND users.banned=0',(tokenhash(t),now)).fetchone(); need(r,'Войдите в аккаунт',401); u=r['uid']
    role=r['role']
    if path=='/announcement' and method=='GET': return {'text':setting(c,'announcement')}
    if path=='/me/password' and method=='POST':
        old=str(d.get('old','')); new=str(d.get('new','')); need(12<=len(new)<=256,'Пароль: от 12 символов',400)
        a=c.execute('SELECT * FROM users WHERE id=?',(u,)).fetchone(); need(len(old)<=256 and hmac.compare_digest(password(old,a['salt']),a['hash']),'Неверный пароль',403)
        salt=secrets.token_hex(16); c.execute('UPDATE users SET salt=?,hash=? WHERE id=?',(salt,password(new,salt),u))
        c.execute('DELETE FROM sessions WHERE uid=? AND token!=?',(u,tokenhash(t))); audit(c,u,'change_password',u); return {'ok':True}
    if path=='/me/sessions' and method=='POST':
        c.execute('DELETE FROM sessions WHERE uid=? AND token!=?',(u,tokenhash(t))); return {'ok':True}
    if path=='/blocks':
        if method=='GET': return [dict(x) for x in c.execute('SELECT users.id,users.name,users.username FROM blocks JOIN users ON users.id=blocks.blocked WHERE uid=?',(u,))]
        other=int(d.get('uid',0)); need(other!=u and c.execute('SELECT 1 FROM users WHERE id=?',(other,)),'Пользователь не найден',404)
        if d.get('blocked',True):
            c.execute('INSERT OR IGNORE INTO blocks VALUES(?,?)',(u,other)); c.execute("UPDATE calls SET status='ended' WHERE (caller=? AND callee=?) OR (caller=? AND callee=?)",(u,other,other,u))
        else: c.execute('DELETE FROM blocks WHERE uid=? AND blocked=?',(u,other))
        return {'ok':True}
    if path=='/saved' and method=='GET':
        return [dict(x) for x in c.execute("""SELECT m.id,m.chat,m.kind,CASE WHEN m.kind='text' THEN m.body ELSE '' END AS body,m.filename,m.created
            FROM saved_messages s JOIN messages m ON s.message=m.id JOIN members ON members.chat=m.chat AND members.uid=s.uid
            WHERE s.uid=? AND m.deleted=0 ORDER BY m.id DESC LIMIT 200""",(u,))]
    if route[0]=='admin':
        need(role=='owner','Только владелец Telezeka',403)
        if path=='/admin/stats' and method=='GET':
            return {'users':c.execute('SELECT COUNT(*) FROM users').fetchone()[0],'banned':c.execute('SELECT COUNT(*) FROM users WHERE banned=1').fetchone()[0],
              'groups':c.execute("SELECT COUNT(*) FROM chats WHERE kind='group'").fetchone()[0],'channels':c.execute("SELECT COUNT(*) FROM chats WHERE kind='channel'").fetchone()[0],
              'messages':c.execute('SELECT COUNT(*) FROM messages WHERE deleted=0').fetchone()[0],'registration':setting(c,'registration'),'announcement':setting(c,'announcement')}
        if path=='/admin/users' and method=='GET':
            return [dict(x) for x in c.execute('SELECT id,name,username,role,banned FROM users ORDER BY id LIMIT 1000')]
        if path=='/admin/ban' and method=='POST':
            target=int(d.get('uid',0)); a=c.execute('SELECT role FROM users WHERE id=?',(target,)).fetchone(); need(a and a['role']!='owner','Нельзя заблокировать владельца',403)
            ban=int(bool(d.get('banned',True))); c.execute('UPDATE users SET banned=? WHERE id=?',(ban,target))
            if ban:
                c.execute('DELETE FROM sessions WHERE uid=?',(target,)); c.execute("UPDATE calls SET status='ended' WHERE caller=? OR callee=?",(target,target))
            audit(c,u,'ban' if ban else 'unban',target); return {'ok':True}
        if path=='/admin/settings' and method=='POST':
            if 'registration' in d:
                need(d['registration'] in ('open','closed'),'Неверный режим',400); c.execute("UPDATE settings SET value=? WHERE key='registration'",(d['registration'],))
            if 'announcement' in d: c.execute("UPDATE settings SET value=? WHERE key='announcement'",(clean(d['announcement'],1000),))
            audit(c,u,'settings'); return {'ok':True}
        if path=='/admin/rooms' and method=='GET':
            return [dict(x) for x in c.execute("SELECT id,title,kind,owner,(SELECT COUNT(*) FROM members WHERE chat=chats.id) AS member_count FROM chats WHERE kind!='direct' ORDER BY id LIMIT 1000")]
        if path=='/admin/room_rename' and method=='POST':
            target=int(d.get('chat',0)); title=clean(d.get('title')); need(title,'Укажите название',400)
            need(c.execute("SELECT 1 FROM chats WHERE id=? AND kind!='direct'",(target,)),'Группа или канал не найдены',404)
            c.execute('UPDATE chats SET title=? WHERE id=?',(title,target)); audit(c,u,'room_rename',target); return {'ok':True}
        if path=='/admin/audit' and method=='GET':
            return [dict(x) for x in c.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 200')]
        if path=='/admin/reports' and method=='GET':
            return [dict(x) for x in c.execute('SELECT reports.id,reporter,message,reason,status,created FROM reports ORDER BY id DESC LIMIT 200')]
        if path=='/admin/report_close' and method=='POST':
            target=int(d.get('id',0)); c.execute("UPDATE reports SET status='closed' WHERE id=?",(target,)); audit(c,u,'report_close',target); return {'ok':True}
        raise Err(404,'Не найдено')
    if path=='/logout' and method=='POST': c.execute('DELETE FROM sessions WHERE token=?',(tokenhash(t),)); return {'ok':True}
    if path=='/me':
        if method=='POST':
            n=clean(d.get('name')); un=username(d.get('username')); need(n,'Укажите имя',400); need(un!='zakaria' or role=='owner','Имя зарезервировано',409); c.execute('UPDATE users SET name=?,username=?,bio=COALESCE(?,bio) WHERE id=?',(n,un,clean(d['bio'],200) if 'bio' in d else None,u))
        return public(c.execute('SELECT * FROM users WHERE id=?',(u,)).fetchone())
    if path=='/chats':
        if method=='GET':
            rows=c.execute('SELECT chats.* FROM chats JOIN members ON chats.id=members.chat WHERE members.uid=? ORDER BY COALESCE((SELECT MAX(id) FROM messages WHERE chat=chats.id),0) DESC,chats.id DESC',(u,)).fetchall(); out=[]
            for x in rows:
                a=dict(x); people=c.execute('SELECT users.id,users.name,users.username FROM users JOIN members ON users.id=members.uid WHERE members.chat=?',(x['id'],)).fetchall(); a['members']=[dict(y) for y in people]; a['title']=next((y['name'] for y in people if y['id']!=u),'Личный чат') if x['kind']=='direct' else x['title']; a.pop('direct_key',None); pref=c.execute('SELECT favorite,archived,muted FROM chat_prefs WHERE uid=? AND chat=?',(u,x['id'])).fetchone(); a.update(dict(pref) if pref else {'favorite':0,'archived':0,'muted':0}); a['unread']=c.execute('SELECT COUNT(*) FROM messages WHERE chat=? AND sender!=? AND deleted=0 AND id>COALESCE((SELECT last_id FROM read_marks WHERE chat=? AND uid=?),0)',(x['id'],u,x['id'],u)).fetchone()[0]; pin=c.execute('SELECT m.id,m.kind,m.body FROM pins JOIN messages m ON pins.message=m.id WHERE pins.chat=? AND m.deleted=0',(x['id'],)).fetchone(); a['pin']=dict(id=pin['id'],preview=pin['body'][:160] if pin['kind']=='text' else 'Вложение') if pin else None; out.append(a)
            return out
        k=d.get('kind'); need(k in ('direct','group','channel'),'Неверный тип',400)
        if k=='direct':
            other=peer(c,d.get('username'))['id']; need(other!=u,'Выберите другого пользователя',400); need(not blocked(c,u,other),'Общение недоступно',403); key=':'.join(map(str,sorted([u,other]))); old=c.execute('SELECT id FROM chats WHERE direct_key=?',(key,)).fetchone()
            if old:return {'id':old['id']}
            ch=c.execute('INSERT INTO chats(title,kind,owner,direct_key) VALUES(?,?,?,?)',('',k,u,key)).lastrowid; c.execute('INSERT INTO members VALUES(?,?)',(ch,other))
        else:
            title=clean(d.get('title')); need(title,'Укажите название',400); ch=c.execute('INSERT INTO chats(title,kind,owner) VALUES(?,?,?)',(title,k,u)).lastrowid
        c.execute('INSERT INTO members VALUES(?,?)',(ch,u)); return {'id':ch}
    if len(route)==3 and route[0]=='chats':
        ch=int(route[1]); room=member(c,u,ch); action=route[2]
        if action=='prefs' and method=='POST':
            c.execute('INSERT OR IGNORE INTO chat_prefs(uid,chat) VALUES(?,?)',(u,ch))
            for key in ('favorite','archived','muted'):
                if key in d: c.execute(f'UPDATE chat_prefs SET {key}=? WHERE uid=? AND chat=?',(int(bool(d[key])),u,ch))
            return {'ok':True}
        if action=='leave' and method=='POST':
            need(room['kind']!='direct' and room['owner']!=u,'Владелец или участник личного чата не может выйти',400)
            c.execute('DELETE FROM members WHERE chat=? AND uid=?',(ch,u)); return {'ok':True}
        if action=='invite' and method=='POST':
            need(room['owner']==u and room['kind']!='direct'); other=peer(c,d.get('username'))['id']; c.execute('INSERT OR IGNORE INTO members VALUES(?,?)',(ch,other)); return {'ok':True}
        if action=='messages':
            if method=='GET':
                if 'recent' in q: return message_rows(c,u,ch,limit=200,descending=True)
                if 'before' in q: return message_rows(c,u,ch,'AND m.id<?',(int(q['before'][0]),),descending=True)
                return message_rows(c,u,ch,'AND m.id>?',(int(q.get('after',['0'])[0]),),limit=100)
            need(method=='POST' and (room['kind']!='channel' or room['owner']==u)); check_direct(c,u,room); k=d.get('kind','text'); b=str(d.get('body','')); need(k in ('text','voice','circle','file','photo'),'Неверный тип',400)
            reply=d.get('reply_to'); filename=None
            if reply is not None: need(c.execute('SELECT 1 FROM messages WHERE chat=? AND id=? AND deleted=0',(ch,int(reply))).fetchone(),'Ответ на недоступное сообщение',400)
            if k in ('file','photo'):
                filename=clean(d.get('filename'),180); need(filename and not any(x in filename for x in ('/',chr(92),chr(0))),'Некорректное имя файла',400)
            if k=='text': need(0<len(b.strip())<=12000,'Пустое или слишком длинное сообщение',400)
            else:
                need(len(b)<=LIMIT,'Файл слишком большой',413)
                try: raw=base64.b64decode(b,validate=True); need(0<len(raw)<=16*1024*1024,'Файл слишком большой',413)
                except ValueError: raise Err(400,'Некорректный файл')
            mid=c.execute('INSERT INTO messages(chat,sender,kind,body,created,reply_to,filename) VALUES(?,?,?,?,?,?,?)',(ch,u,k,b,now,reply,filename)).lastrowid; return {'id':mid}
        if action=='read' and method=='POST':
            mid=int(d.get('id',0)); need(c.execute('SELECT 1 FROM messages WHERE chat=? AND id=?',(ch,mid)).fetchone(),'Сообщение не найдено',404)
            c.execute('INSERT INTO read_marks VALUES(?,?,?) ON CONFLICT(chat,uid) DO UPDATE SET last_id=MAX(last_id,excluded.last_id)',(ch,u,mid)); return {'ok':True}
        if action=='search' and method=='GET':
            term=clean(q.get('q',[''])[0],120); need(term,'Введите запрос',400)
            return message_rows(c,u,ch,"AND m.deleted=0 AND m.kind='text' AND instr(casefold(m.body),casefold(?))>0",(term,),limit=100,descending=True)
        if action=='rename' and method=='POST':
            need(room['owner']==u and room['kind']!='direct'); title=clean(d.get('title')); need(title,'Укажите название',400); c.execute('UPDATE chats SET title=? WHERE id=?',(title,ch)); return {'ok':True}
        if action=='remove_member' and method=='POST':
            need(room['owner']==u and room['kind']!='direct'); other=int(d.get('uid',0)); need(other!=u,'Нельзя удалить владельца',400); c.execute('DELETE FROM members WHERE chat=? AND uid=?',(ch,other)); c.execute('DELETE FROM read_marks WHERE chat=? AND uid=?',(ch,other)); return {'ok':True}
        if action=='pin' and method=='POST':
            need(room['kind']=='direct' or room['owner']==u); mid=d.get('id');
            if mid is None: c.execute('DELETE FROM pins WHERE chat=?',(ch,))
            else:
                need(c.execute('SELECT 1 FROM messages WHERE chat=? AND id=? AND deleted=0',(ch,int(mid))).fetchone(),'Сообщение не найдено',404); c.execute('INSERT INTO pins VALUES(?,?) ON CONFLICT(chat) DO UPDATE SET message=excluded.message',(ch,int(mid)))
            return {'ok':True}
        if action=='call' and method=='POST':
            need(room['kind']=='direct','Звонки только в личных чатах',400); check_direct(c,u,room); other=c.execute('SELECT uid FROM members WHERE chat=? AND uid!=?',(ch,u)).fetchone()['uid']; c.execute("UPDATE calls SET status='ended' WHERE status IN ('ringing','active') AND (caller IN (?,?) OR callee IN (?,?)) AND created<?",(u,other,u,other,now-7200)); need(not c.execute("SELECT id FROM calls WHERE status IN ('ringing','active') AND (caller IN (?,?) OR callee IN (?,?)) AND (status='active' OR created>?)",(u,other,u,other,now-60)).fetchone(),'Абонент занят',409); cid=c.execute('INSERT INTO calls(chat,caller,callee,video,status,created) VALUES(?,?,?,?,?,?)',(ch,u,other,int(bool(d.get('video'))),'ringing',now)).lastrowid; return {'id':cid}
    if len(route)==3 and route[0]=='messages' and method=='POST':
        mid=int(route[1]); m=c.execute('SELECT * FROM messages WHERE id=?',(mid,)).fetchone(); need(m); room=member(c,u,m['chat']); need(not m['deleted'],'Сообщение удалено',404); act=route[2]
        if act=='save':
            if d.get('saved',True): c.execute('INSERT OR IGNORE INTO saved_messages VALUES(?,?)',(u,mid))
            else: c.execute('DELETE FROM saved_messages WHERE uid=? AND message=?',(u,mid))
            return {'ok':True}
        if act=='report':
            reason=clean(d.get('reason'),500); need(reason,'Укажите причину',400)
            need(not c.execute("SELECT 1 FROM reports WHERE reporter=? AND message=? AND status='open'",(u,mid)),'Жалоба уже отправлена',409)
            c.execute('INSERT INTO reports(reporter,message,reason,created) VALUES(?,?,?,?)',(u,mid,reason,now)); return {'ok':True}
        if act=='edit':
            need(m['sender']==u and m['kind']=='text'); b=str(d.get('body','')).strip(); need(0<len(b)<=12000,'Введите сообщение',400); c.execute('UPDATE messages SET body=?,edited=? WHERE id=?',(b,now,mid)); return {'ok':True}
        if act=='delete':
            need(m['sender']==u or (room['kind']!='direct' and room['owner']==u)); c.execute("UPDATE messages SET deleted=1,body='',filename=NULL WHERE id=?",(mid,)); c.execute('DELETE FROM reactions WHERE message=?',(mid,)); c.execute('DELETE FROM pins WHERE message=?',(mid,)); return {'ok':True}
        if act=='react':
            emoji=d.get('emoji'); need(emoji in ('👍','❤️','😂','😮','😢','🔥',None),'Неизвестная реакция',400)
            old=c.execute('SELECT emoji FROM reactions WHERE message=? AND uid=?',(mid,u)).fetchone()
            if emoji is None or (old and old['emoji']==emoji): c.execute('DELETE FROM reactions WHERE message=? AND uid=?',(mid,u))
            else: c.execute('INSERT INTO reactions VALUES(?,?,?) ON CONFLICT(message,uid) DO UPDATE SET emoji=excluded.emoji',(mid,u,emoji))
            return {'ok':True}
    if path=='/incoming' and method=='GET':
        rows=c.execute("SELECT calls.*,users.name FROM calls JOIN users ON calls.caller=users.id WHERE callee=? AND status='ringing' AND created>? ORDER BY id DESC LIMIT 1",(u,now-60)).fetchall(); return [dict(x) for x in rows]
    if len(route)==2 and route[0]=='media' and method=='GET':
        r=c.execute('SELECT * FROM messages WHERE id=?',(int(route[1]),)).fetchone(); need(r); member(c,u,r['chat']); need(r['kind']!='text' and not r['deleted']); return {'body':r['body'],'filename':r['filename'],'kind':r['kind']}
    if len(route)==3 and route[0]=='calls':
        cid=int(route[1]); a=c.execute('SELECT * FROM calls WHERE id=?',(cid,)).fetchone(); need(a and u in (a['caller'],a['callee'])); act=route[2]
        if act=='status':
            if method=='POST':
                new=d.get('status'); need(new=='ended' or (new=='active' and u==a['callee'] and a['status']=='ringing' and a['created']>now-60)); c.execute('UPDATE calls SET status=? WHERE id=?',(new,cid))
            return dict(c.execute('SELECT * FROM calls WHERE id=?',(cid,)).fetchone())
        if act=='signals':
            if method=='GET': return [dict(x) for x in c.execute('SELECT * FROM signals WHERE call=? AND sender!=? AND id>? ORDER BY id LIMIT 100',(cid,u,int(q.get('after',['0'])[0])))]
            need(a['status'] in ('ringing','active')); payload=json.dumps(d); need(len(payload)<100000,'Слишком большой сигнал',400); c.execute('INSERT INTO signals(call,sender,payload) VALUES(?,?,?)',(cid,u,payload)); return {'ok':True}
    raise Err(404,'Не найдено')

# Bound authentication attempts globally and per email; in-memory limits reset on restart.
_attempts={}
_attempt_lock=threading.Lock()
def check_auth_limit(email):
    now=time.monotonic()
    with _attempt_lock:
        for k in list(_attempts):
            if now-_attempts[k][0]>60: _attempts.pop(k,None)
        for key,limit in [('global',60),('email:'+clean(email,254).lower(),8)]:
            start,count=_attempts.get(key,(now,0))
            need(count<limit,'Слишком много попыток. Повторите позже.',429)
            _attempts[key]=(start,count+1)

class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup(); self.connection.settimeout(20)
    def do_GET(self): self.handle_api('GET')
    def do_POST(self): self.handle_api('POST')
    def handle_api(self,method):
        try:
            parsed=urlparse(self.path); d={}; size=int(self.headers.get('Content-Length','0')); need(0<=size<=LIMIT,'Слишком большой запрос',413)
            if size: d=json.loads(self.rfile.read(size)); need(isinstance(d,dict),'Некорректный запрос',400)
            if method=='POST' and parsed.path in ('/register','/login'): check_auth_limit(d.get('email'))
            with closing(db()) as c,c: result=run(c,method,parsed.path,parse_qs(parsed.query),d,self.headers.get('Authorization',''))
            self.reply(200,result)
        except Err as e:self.reply(e.status,{'error':e.msg})
        except sqlite3.IntegrityError:self.reply(409,{'error':'Email или username уже занят, либо конфликт данных'})
        except (ValueError,TypeError,KeyError):self.reply(400,{'error':'Некорректный запрос'})
        except (BrokenPipeError,ConnectionResetError,TimeoutError): return
        except Exception as e: print(type(e).__name__,flush=True); self.reply(500,{'error':'Ошибка сервера'})
    def reply(self,status,data):
        b=json.dumps(data,ensure_ascii=False).encode(); self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self,*args): pass

if __name__=='__main__':
    if not INVITE: raise SystemExit('Установите CHAT_INVITE — секретный код регистрации')
    init(); ThreadingHTTPServer((os.getenv('CHAT_HOST','127.0.0.1'),int(os.getenv('CHAT_PORT','8080'))),Handler).serve_forever()
