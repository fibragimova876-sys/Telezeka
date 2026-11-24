"""Compare Rust read routes against the existing Python API and verify access control."""
import os, sys, json, time, tempfile, subprocess, urllib.request, urllib.error
from pathlib import Path
from contextlib import closing
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'server'))
import server as s
def request(port,path,token=None,data=None):
    req=urllib.request.Request(f'http://127.0.0.1:{port}{path}',data=json.dumps(data).encode() if data is not None else None,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
    try:
        with urllib.request.urlopen(req,timeout=5) as r: return r.status,json.load(r)
    except urllib.error.HTTPError as e: return e.code,json.load(e)
with tempfile.TemporaryDirectory() as tmp:
    s.DB=tmp+'/chat.db'; os.environ['TELEZEKA_OWNER_PASSWORD']='temporary-test-owner-password'
    s.init()
    with closing(s.db()) as c,c:
        owner=c.execute("SELECT id FROM users WHERE role='owner'").fetchone()[0]
        def add(name):
            salt='a'*32
            return c.execute('INSERT INTO users(name,username,email,salt,hash) VALUES(?,?,?,?,?)',(name,name,name+'@example.test',salt,s.password('test-password',salt))).lastrowid
        alice=add('alice'); bob=add('bob'); outsider=add('outsider')
        tokens={u:s.session(c,u)['token'] for u in (owner,alice,bob,outsider)}
        ch=c.execute("INSERT INTO chats(title,kind,owner) VALUES('Family','group',?)",(alice,)).lastrowid
        c.executemany('INSERT INTO members VALUES(?,?)',[(ch,alice),(ch,bob)])
        mid=c.execute("INSERT INTO messages(chat,sender,kind,body,created) VALUES(?,?,'text','hello',?)",(ch,bob,int(time.time()))).lastrowid
        c.execute("INSERT INTO reactions VALUES(?,?,?)",(mid,alice,'👍'))
        c.execute("INSERT INTO pins VALUES(?,?)",(ch,mid))
    env=dict(os.environ,CHAT_DB=s.DB,CHAT_INVITE='test-only',CHAT_PORT='8080',PORT='8080',TELEZEKA_RUST_BIN=str(root/'rust-core/target/release/telezeka-core'))
    p=subprocess.Popen([sys.executable,str(root/'scripts/run_hybrid.py')],env=env)
    try:
        for i in range(100):
            try:
                if request(8080,'/health')[0]==200: break
            except OSError: time.sleep(.2)
        else: raise RuntimeError('Rust gateway failed to start')
        for path in ('/chats',f'/chats/{ch}/messages?recent=1',f'/chats/{ch}/messages?after=0',f'/chats/{ch}/messages?before={mid+1}','/announcement','/incoming'):
            py=request(8081,path,tokens[alice])
            rust=request(8080,path,tokens[alice])
            assert py==rust,(path,py,rust)
        assert request(8080,'/chats')[0]==401
        for u in (outsider,owner): assert request(8080,f'/chats/{ch}/messages?recent=1',tokens[u])[0]==403
        assert request(8080,f'/chats/{ch}/messages',tokens[alice],{'kind':'text','body':'Rust gateway write'})[0]==200
        assert request(8080,f'/chats/{ch}/messages?recent=1',tokens[bob])[1][-1]['body']=='Rust gateway write'
        with closing(s.db()) as c,c: c.execute('UPDATE users SET banned=1 WHERE id=?',(alice,))
        assert request(8080,'/chats',tokens[alice])[0]==401
        print('Rust/Python API parity, proxy writes, membership and banned-account checks passed')
    finally:
        p.terminate()
        try:p.wait(timeout=15)
        except subprocess.TimeoutExpired:p.kill();p.wait()
