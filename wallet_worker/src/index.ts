export interface Env { DB:D1Database; MONGIKE_API_KEY:string; MONGIKE_BASE_URL:string; MONGIKE_COLLECTION_PATH:string; MONGIKE_STATUS_PATH:string; WALLET_CLIENT_TOKEN:string; }
const json=(x:unknown,s=200)=>new Response(JSON.stringify(x),{status:s,headers:{'content-type':'application/json','access-control-allow-origin':'*'}});
const id=()=>crypto.randomUUID();
function auth(r:Request,e:Env){const h=r.headers.get('authorization')||'';return e.WALLET_CLIENT_TOKEN&&h===`Bearer ${e.WALLET_CLIENT_TOKEN}`;}
export default {async fetch(r:Request,e:Env):Promise<Response>{
 if(r.method==='OPTIONS')return new Response(null,{headers:{'access-control-allow-origin':'*','access-control-allow-methods':'GET,POST,OPTIONS','access-control-allow-headers':'content-type,authorization'}});
 const u=new URL(r.url); if(!auth(r,e))return json({error:'Unauthorized'},401);
 try{
  if(u.pathname==='/wallet/balance'&&r.method==='GET'){const w=await e.DB.prepare('SELECT balance_tzs AS balance FROM wallets WHERE id=?').bind('owner').first<{balance:number}>();return json({balance:w?.balance??0,currency:'TZS'});}
  if(u.pathname==='/wallet/deposit'&&r.method==='POST'){
   const b=await r.json() as {amount:number;phone:string;provider:string}; if(!Number.isInteger(b.amount)||b.amount<500||!b.phone||!b.provider)return json({error:'Invalid deposit'},400);
   await e.DB.prepare('INSERT OR IGNORE INTO wallets(id,balance_tzs) VALUES(?,0)').bind('owner').run();
   const pid=id(); await e.DB.prepare('INSERT INTO payments(id,wallet_id,amount_tzs,phone,provider,status) VALUES(?,?,?,?,?,?)').bind(pid,'owner',b.amount,b.phone,b.provider,'PENDING').run();
   if(!e.MONGIKE_BASE_URL||!e.MONGIKE_COLLECTION_PATH)return json({paymentId:pid,status:'PENDING',message:'Payment order created; Mongike live adapter is not configured yet.'},202);
   const endpoint=e.MONGIKE_BASE_URL.replace(/\/$/,'')+e.MONGIKE_COLLECTION_PATH;
   const mr=await fetch(endpoint,{method:'POST',headers:{'content-type':'application/json','authorization':`Bearer ${e.MONGIKE_API_KEY}`,'idempotency-key':pid},body:JSON.stringify({amount:b.amount,phone:b.phone,provider:b.provider,reference:pid})});
   const text=await mr.text();let data:unknown;try{data=JSON.parse(text)}catch{data={raw:text}};
   if(!mr.ok){await e.DB.prepare('UPDATE payments SET status=?,updated_at=CURRENT_TIMESTAMP WHERE id=?').bind('FAILED',pid).run();return json({error:'Mongike rejected payment',paymentId:pid,providerResponse:data},502);}
   const mongikeId=typeof data==='object'&&data!==null?String((data as any).id??(data as any).payment_id??''):'';
   await e.DB.prepare('UPDATE payments SET mongike_id=?,updated_at=CURRENT_TIMESTAMP WHERE id=?').bind(mongikeId||null,pid).run();
   return json({paymentId:pid,status:'PENDING',message:'Payment request sent. Approve the prompt on your phone.',providerResponse:data},202);
  }
  if(u.pathname==='/webhooks/mongike'&&r.method==='POST'){
   const raw=await r.text();const eventId=id();await e.DB.prepare('INSERT OR IGNORE INTO webhook_events(id,payload) VALUES(?,?)').bind(eventId,raw).run();let b:any;try{b=JSON.parse(raw)}catch{return json({ok:true});}
   const paymentId=String(b.reference??b.merchant_reference??b.metadata?.reference??'');const externalId=String(b.id??b.payment_id??'');const state=String(b.status??'').toUpperCase();
   const p=paymentId?await e.DB.prepare('SELECT * FROM payments WHERE id=?').bind(paymentId).first<any>():externalId?await e.DB.prepare('SELECT * FROM payments WHERE mongike_id=?').bind(externalId).first<any>():null;
   if(!p)return json({ok:true}); if(['SUCCESS','COMPLETED','PAID'].includes(state)&&p.status!=='SUCCESS'){
    const w=await e.DB.prepare('SELECT balance_tzs FROM wallets WHERE id=?').bind(p.wallet_id).first<{balance_tzs:number}>();const after=(w?.balance_tzs??0)+p.amount_tzs;
    await e.DB.batch([e.DB.prepare('UPDATE wallets SET balance_tzs=?,updated_at=CURRENT_TIMESTAMP WHERE id=?').bind(after,p.wallet_id),e.DB.prepare('UPDATE payments SET status=?,updated_at=CURRENT_TIMESTAMP WHERE id=?').bind('SUCCESS',p.id),e.DB.prepare('INSERT INTO ledger(id,wallet_id,payment_id,type,amount_tzs,balance_after,reference) VALUES(?,?,?,?,?,?,?)').bind(id(),p.wallet_id,p.id,'DEPOSIT',p.amount_tzs,after,p.id)]);
   } else if(['FAILED','CANCELLED','EXPIRED'].includes(state)){await e.DB.prepare('UPDATE payments SET status=?,updated_at=CURRENT_TIMESTAMP WHERE id=?').bind(state,p.id).run();}
   return json({ok:true});
  }
  return json({error:'Not found'},404);
 }catch(err){return json({error:'Server error',detail:String(err)},500);}
}};
