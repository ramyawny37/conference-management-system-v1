import { createClient } from '@supabase/supabase-js';import webpush from 'web-push';
const ORIGIN='https://ramyawny37.github.io',cors={'Access-Control-Allow-Origin':ORIGIN,'Access-Control-Allow-Headers':'authorization, content-type, apikey','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Vary':'Origin'};
function required(name:string){const v=String(Deno.env.get(name)||'').trim();if(!v)throw new Error('MISSING_'+name);return v}
function json(status:number,body:unknown){return new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}})}
function bearer(req:Request){return String(req.headers.get('Authorization')||'').replace(/^Bearer\s+/,'')}
Deno.serve(async req=>{if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});try{
 if(req.headers.get('Origin')!==ORIGIN)throw new Error('PLATFORM_NOTIFICATION_ORIGIN_DENIED');
 if(req.method==='GET'){return json(200,{ok:true,data:{vapidPublicKey:required('PLATFORM_WEB_PUSH_VAPID_PUBLIC_KEY')}})}
 if(req.method!=='POST')return json(405,{ok:false,error:{code:'METHOD_NOT_ALLOWED'}});
 const serviceKey=required('SUPABASE_SERVICE_ROLE_KEY');if(bearer(req)!==serviceKey)throw new Error('PLATFORM_NOTIFICATION_BACKEND_REQUIRED');
 const body=await req.json();if(!body||body.operation!=='emit'||!body.event||typeof body.event!=='object')throw new Error('PLATFORM_NOTIFICATION_ARGUMENT_INVALID');
 const service=createClient(required('SUPABASE_URL'),serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const event=body.event;const queued=await service.schema('platform').rpc('notification_gateway',{p_operation:'enqueue',p_args:event});if(queued.error)throw queued.error;
 webpush.setVapidDetails(required('PLATFORM_WEB_PUSH_VAPID_SUBJECT'),required('PLATFORM_WEB_PUSH_VAPID_PUBLIC_KEY'),required('PLATFORM_WEB_PUSH_VAPID_PRIVATE_KEY'));
 const pending=await service.schema('platform').rpc('notification_gateway',{p_operation:'pending',p_args:{limit:100}});if(pending.error)throw pending.error;
 let sent=0,failed=0;for(const item of Array.isArray(pending.data)?pending.data:[]){let status='sent',errorCode='';try{await webpush.sendNotification({endpoint:item.endpoint,keys:{p256dh:item.p256dh,auth:item.auth}},JSON.stringify({title:item.title,body:item.body,url:item.targetUrl,type:item.eventType}),{TTL:86400,urgency:'high'});sent++}catch(error){const code=Number((error as {statusCode?:number}).statusCode||0);status=code===404||code===410?'expired':'failed';errorCode=code?String(code):'WEB_PUSH_SEND_FAILED';failed++}const marked=await service.schema('platform').rpc('notification_gateway',{p_operation:'mark',p_args:{deliveryId:item.deliveryId,status,errorCode}});if(marked.error)console.error(JSON.stringify({code:'PLATFORM_NOTIFICATION_MARK_FAILED',deliveryId:item.deliveryId}))}
 return json(200,{ok:true,data:{notificationEventId:queued.data?.notificationEventId||null,sent,failed}});
 }catch(error){const raw=String((error as {message?:unknown})?.message||error||'');const code=/^[A-Z][A-Z0-9_]{2,95}$/.test(raw)?raw:'PLATFORM_NOTIFICATION_FAILED';console.error(JSON.stringify({code,timestamp:new Date().toISOString()}));return json(code==='PLATFORM_NOTIFICATION_BACKEND_REQUIRED'?403:code.startsWith('MISSING_')?503:422,{ok:false,error:{code}})}});
