use axum::{body::{Body,to_bytes},extract::{Request,State},http::{Method,StatusCode,HeaderMap,Uri,header},response::{IntoResponse,Response},Router};
use serde_json::{json,Value};
use sha2::{Digest,Sha256};
use sqlx::{SqlitePool,Sqlite,Transaction,sqlite::{SqliteConnectOptions,SqlitePoolOptions}};
use std::{env,time::{Duration,SystemTime,UNIX_EPOCH}};
#[derive(Clone)]
struct App { db: SqlitePool, upstream: reqwest::Client, origin: String }
type ApiResult<T> = Result<T,(StatusCode,&'static str)>;
fn internal(_:sqlx::Error)->(StatusCode,&'static str){(StatusCode::INTERNAL_SERVER_ERROR,"Ошибка сервера")}
fn unauthorized()->(StatusCode,&'static str){(StatusCode::UNAUTHORIZED,"Войдите в аккаунт")}
fn forbidden()->(StatusCode,&'static str){(StatusCode::FORBIDDEN,"Нет доступа")}
fn error(e:(StatusCode,&'static str))->Response{(e.0,[(header::CACHE_CONTROL,"no-store")],axum::Json(json!({"error":e.1}))).into_response()}
fn now()->i64{SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs() as i64}
async fn auth(tx:&mut Transaction<'_,Sqlite>,headers:&HeaderMap)->ApiResult<i64>{
    let token=headers.get(header::AUTHORIZATION).and_then(|v|v.to_str().ok()).and_then(|v|v.strip_prefix("Bearer ")).filter(|v|!v.is_empty()&&v.len()<=256).ok_or_else(unauthorized)?;
    let hash=hex::encode(Sha256::digest(token.as_bytes()));
    sqlx::query_scalar::<_,i64>("SELECT sessions.uid FROM sessions JOIN users ON users.id=sessions.uid WHERE token=? AND expires>? AND users.banned=0")
       .bind(hash).bind(now()).fetch_optional(&mut **tx).await.map_err(internal)?.ok_or_else(unauthorized)
}
const CHATS:&str=r#"
SELECT json_object('id',c.id,'title',CASE WHEN c.kind='direct' THEN COALESCE((SELECT u.name FROM members m JOIN users u ON u.id=m.uid WHERE m.chat=c.id AND m.uid<>?1 LIMIT 1),'Личный чат') ELSE c.title END,
'kind',c.kind,'owner',c.owner,'members',json(COALESCE((SELECT json_group_array(json_object('id',u.id,'name',u.name,'username',u.username)) FROM members m JOIN users u ON u.id=m.uid WHERE m.chat=c.id),'[]')),
'favorite',COALESCE(p.favorite,0),'archived',COALESCE(p.archived,0),'muted',COALESCE(p.muted,0),
'unread',(SELECT COUNT(*) FROM messages m WHERE m.chat=c.id AND m.sender<>?1 AND m.deleted=0 AND m.id>COALESCE((SELECT last_id FROM read_marks WHERE chat=c.id AND uid=?1),0)),
'pin',json((SELECT json_object('id',m.id,'preview',CASE WHEN m.kind='text' THEN substr(m.body,1,160) ELSE 'Вложение' END) FROM pins x JOIN messages m ON m.id=x.message WHERE x.chat=c.id AND m.deleted=0)))
FROM chats c JOIN members a ON a.chat=c.id AND a.uid=?1 LEFT JOIN chat_prefs p ON p.chat=c.id AND p.uid=?1
ORDER BY COALESCE((SELECT MAX(id) FROM messages WHERE chat=c.id),0) DESC,c.id DESC
"#;
const MESSAGES:&str=r#"
SELECT json_object('id',m.id,'sender',m.sender,'kind',m.kind,'body',CASE WHEN m.deleted=0 AND m.kind='text' THEN m.body ELSE '' END,
'created',m.created,'name',u.name,'edited',m.edited,'deleted',m.deleted,'reply_to',CASE WHEN m.deleted=0 THEN m.reply_to END,
'filename',CASE WHEN m.deleted=0 THEN m.filename END,'reply_preview',CASE WHEN m.deleted=1 THEN NULL WHEN r.deleted=1 THEN 'Сообщение удалено' WHEN r.kind='text' THEN substr(r.body,1,160) ELSE 'Вложение' END,
'reactions',json(CASE WHEN m.deleted=1 THEN '[]' ELSE COALESCE((SELECT json_group_array(json_object('emoji',emoji,'count',n,'mine',mine)) FROM (SELECT emoji,COUNT(*) AS n,MAX(uid=?1) AS mine FROM reactions WHERE message=m.id GROUP BY emoji)),'[]') END))
FROM messages m JOIN users u ON u.id=m.sender LEFT JOIN messages r ON r.id=m.reply_to AND r.chat=m.chat
WHERE m.chat=?2 AND (?3=0 OR (?3=1 AND m.id<?4) OR (?3=2 AND m.id>?4))
ORDER BY CASE WHEN ?3=2 THEN m.id END ASC,CASE WHEN ?3<>2 THEN m.id END DESC LIMIT ?5
"#;
fn parse_rows(rows:Vec<String>)->ApiResult<Value>{
    rows.into_iter().map(|s|serde_json::from_str::<Value>(&s).map_err(|_|(StatusCode::INTERNAL_SERVER_ERROR,"Ошибка сервера"))).collect::<ApiResult<Vec<_>>>().map(Value::Array)
}
async fn native(app:&App,method:&Method,uri:&Uri,headers:&HeaderMap)->ApiResult<Option<Value>>{
    if *method!=Method::GET{return Ok(None)}
    let path=uri.path();
    let parts:Vec<&str>=path.trim_matches('/').split('/').collect();
    let messages=parts.len()==3&&parts[0]=="chats"&&parts[2]=="messages";
    if !matches!(path,"/chats"|"/announcement"|"/incoming")&&!messages{return Ok(None)}
    let mut tx=app.db.begin().await.map_err(internal)?;
    let uid=auth(&mut tx,headers).await?;
    let result=if path=="/chats"{
        parse_rows(sqlx::query_scalar::<_,String>(CHATS).bind(uid).fetch_all(&mut *tx).await.map_err(internal)?)?
    }else if path=="/announcement"{
        let s=sqlx::query_scalar::<_,String>("SELECT value FROM settings WHERE key='announcement'").fetch_one(&mut *tx).await.map_err(internal)?;
        json!({"text":s})
    }else if path=="/incoming"{
        parse_rows(sqlx::query_scalar::<_,String>("SELECT json_object('id',c.id,'chat',c.chat,'caller',c.caller,'callee',c.callee,'video',c.video,'status',c.status,'created',c.created,'name',u.name) FROM calls c JOIN users u ON u.id=c.caller WHERE c.callee=? AND c.status='ringing' AND c.created>? ORDER BY c.id DESC LIMIT 1").bind(uid).bind(now()-60).fetch_all(&mut *tx).await.map_err(internal)?)?
    }else{
        let bad=(StatusCode::BAD_REQUEST,"Некорректный запрос");
        let chat=parts[1].parse::<i64>().map_err(|_|bad)?;
        let ok=sqlx::query_scalar::<_,i64>("SELECT 1 FROM members WHERE chat=? AND uid=?").bind(chat).bind(uid).fetch_optional(&mut *tx).await.map_err(internal)?;
        if ok.is_none(){return Err(forbidden())}
        let q:Vec<(String,String)>=uri.query().unwrap_or("").split('&').filter(|x|!x.is_empty()).map(|s|{let(k,v)=s.split_once('=').unwrap_or((s,""));(k.to_owned(),v.to_owned())}).collect();
        let (mode,bound,limit)=if q.iter().any(|(k,_)|k=="recent"){(0_i64,0_i64,200_i64)}else if let Some((_,v))=q.iter().find(|(k,_)|k=="before"){(1,v.parse::<i64>().map_err(|_|bad)?,200)}else{(2,q.iter().find(|(k,_)|k=="after").map(|(_,v)|v.parse::<i64>()).transpose().map_err(|_|bad)?.unwrap_or(0),100)};
        let mut rows=sqlx::query_scalar::<_,String>(MESSAGES).bind(uid).bind(chat).bind(mode).bind(bound).bind(limit).fetch_all(&mut *tx).await.map_err(internal)?;
        if mode!=2{rows.reverse();}
        parse_rows(rows)?
    };
    tx.commit().await.map_err(internal)?;
    Ok(Some(result))
}
async fn dispatch(State(app):State<App>,req:Request)->Response{
    let method=req.method().clone();let uri=req.uri().clone();let headers=req.headers().clone();
    match native(&app,&method,&uri,&headers).await{
        Ok(Some(v))=>return ([(header::CACHE_CONTROL,"no-store")],axum::Json(v)).into_response(),
        Err(e)=>return error(e),
        _=>{}
    }
    let (parts,body)=req.into_parts();
    if !matches!(parts.method,Method::GET|Method::POST){return error((StatusCode::METHOD_NOT_ALLOWED,"Метод не поддерживается"))}
    let path=parts.uri.path_and_query().map(|v|v.as_str()).unwrap_or("/");
    if !path.starts_with('/')||path.starts_with("//"){return error((StatusCode::BAD_REQUEST,"Некорректный путь"))}
    let mut out=app.upstream.request(parts.method,format!("{}{}",app.origin,path));
    for k in [header::AUTHORIZATION,header::CONTENT_TYPE]{if let Some(v)=parts.headers.get(&k){out=out.header(k,v.clone());}}
    let bytes=match to_bytes(body,24*1024*1024).await{Ok(b)=>b,Err(_)=>return error((StatusCode::PAYLOAD_TOO_LARGE,"Слишком большой запрос"))};
    match out.body(bytes).send().await{
        Ok(r)=>{let status=r.status();match r.bytes().await{Ok(data)=>(status,[(header::CONTENT_TYPE,"application/json; charset=utf-8"),(header::CACHE_CONTROL,"no-store")],Body::from(data)).into_response(),Err(_)=>error((StatusCode::BAD_GATEWAY,"Сервис временно недоступен"))}},
        Err(_)=>error((StatusCode::BAD_GATEWAY,"Сервис временно недоступен"))
    }
}
#[tokio::main]
async fn main()->Result<(),Box<dyn std::error::Error>>{
    let db=env::var("CHAT_DB").unwrap_or_else(|_|"/data/chat.db".into());
    let pool=SqlitePoolOptions::new().max_connections(8).connect_with(SqliteConnectOptions::new().filename(db).read_only(true).busy_timeout(Duration::from_secs(10))).await?;
    let upstream=reqwest::Client::builder().redirect(reqwest::redirect::Policy::none()).connect_timeout(Duration::from_secs(3)).timeout(Duration::from_secs(45)).build()?;
    let app=App{db:pool,upstream,origin:"http://127.0.0.1:8081".into()};
    let port=env::var("PORT").or_else(|_|env::var("CHAT_PORT")).unwrap_or_else(|_|"8080".into()).parse::<u16>()?;
    let listener=tokio::net::TcpListener::bind(("0.0.0.0",port)).await?;
    println!("Telezeka Rust core listening on {port}");
    axum::serve(listener,Router::new().fallback(dispatch).with_state(app)).await?;
    Ok(())
}
