import { createClient } from '@supabase/supabase-js';

const ORIGIN='https://ramyawny37.github.io';
const cors={'Access-Control-Allow-Headers':'content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Origin':ORIGIN,'Vary':'Origin'};
const operations=new Set(['event','submit','status']);
function required(name:string){const value=String(Deno.env.get(name)||'').trim();if(!value)throw new Error('PUBLIC_REGISTRATION_SERVER_CONFIGURATION');return value;}
function json(status:number,body:unknown){return new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});}
function exact(value:unknown,keys:string[]){if(!value||typeof value!=='object'||Array.isArray(value))return false;const actual=Object.keys(value as Record<string,unknown>).sort();return actual.length===keys.length&&actual.every((key,i)=>key===keys.slice().sort()[i]);}
function uuid(value:unknown){const text=String(value||'');if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');return text;}
function bounded(value:unknown,max:number,requiredValue=false){const text=String(value??'');if((requiredValue&&!text.trim())||text.length>max)throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');return text;}
function hex(bytes:Uint8Array){return '\\x'+Array.from(bytes).map(x=>x.toString(16).padStart(2,'0')).join('');}
async function hmac(secret:string,value:string){const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);return new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(value)));}
function b64url(bytes:Uint8Array){return btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');}
function safe(error:unknown){const raw=String((error&&typeof error==='object'&&(error as {message?:unknown}).message)||error||'');if(raw==='PUBLIC_REGISTRATION_RATE_LIMITED')return {status:429,code:raw};if(raw==='PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT')return {status:409,code:raw};if(['PUBLIC_REGISTRATION_UNAVAILABLE','PUBLIC_REGISTRATION_NOT_FOUND'].includes(raw))return {status:404,code:'PUBLIC_REGISTRATION_NOT_FOUND'};if(raw==='PUBLIC_REGISTRATION_CLOSED')return {status:409,code:raw};if(raw.startsWith('PUBLIC_REGISTRATION_')&&raw!=='PUBLIC_REGISTRATION_SERVER_CONFIGURATION')return {status:422,code:raw};return {status:500,code:'PUBLIC_REGISTRATION_FAILED'};}

Deno.serve(async request=>{
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(request.method!=='POST')return json(405,{ok:false,error:{code:'METHOD_NOT_ALLOWED'}});
 try{
  if(request.headers.get('Origin')!==ORIGIN)throw new Error('PUBLIC_REGISTRATION_ORIGIN_DENIED');
  const body=await request.json();
  if(!body||typeof body!=='object'||Array.isArray(body)||!operations.has(String(body.operation||'')))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
  const operation=String(body.operation),args=(body as {args?:unknown}).args;
  const secret=required('PUBLIC_REGISTRATION_HMAC_SECRET');
  const forwarded=String(request.headers.get('x-forwarded-for')||'').split(',')[0].trim();
  const fingerprint=await hmac(secret,'rate:'+forwarded+'|'+String(request.headers.get('user-agent')||'').slice(0,256));
  const service=createClient(required('SUPABASE_URL'),required('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
  let result;
  if(operation==='event'){
    if(!exact(args,['publicId']))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
    result=await service.rpc('public_registration_gateway',{p_operation:'event',p_args:{publicId:uuid((args as any).publicId),fingerprintDigest:hex(fingerprint)}});
  }else if(operation==='status'){
    if(!exact(args,['publicId','trackingSecret']))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
    const a=args as any,tracking=bounded(a.trackingSecret,128,true);
    result=await service.rpc('public_registration_gateway',{p_operation:'status',p_args:{publicId:uuid(a.publicId),trackingSecretDigest:hex(await hmac(secret,'track:'+tracking)),fingerprintDigest:hex(fingerprint)}});
  }else{
    const keys=['bookingTypeId','church','cityOrVillage','dateOfBirth','fullName','gender','governorate','notes','operationId','phone','publicId','serviceSector','serviceSectorOther'];
    if(!exact(args,keys))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
    const a=args as any,publicId=uuid(a.publicId),operationId=uuid(a.operationId);
    const trackingBytes=await hmac(secret,'tracking:'+publicId+':'+operationId),trackingSecret=b64url(trackingBytes);
    result=await service.rpc('public_registration_gateway',{p_operation:'submit',p_args:{
      publicId,submitOperationId:operationId,trackingSecretDigest:hex(await hmac(secret,'track:'+trackingSecret)),fingerprintDigest:hex(fingerprint),
      bookingTypeId:uuid(a.bookingTypeId),fullName:bounded(a.fullName,200,true),phone:bounded(a.phone,20,true),
      gender:a.gender===null?null:bounded(a.gender,12),dateOfBirth:a.dateOfBirth===null?null:bounded(a.dateOfBirth,10),
      church:bounded(a.church,200),governorate:bounded(a.governorate,120),cityOrVillage:bounded(a.cityOrVillage,160),
      serviceSector:bounded(a.serviceSector,160),serviceSectorOther:a.serviceSectorOther===null?null:bounded(a.serviceSectorOther,200),
      notes:a.notes===null?null:bounded(a.notes,4000)
    }});
    if(!result.error){result={...result,data:{...result.data,trackingSecret}};try{const emitted=await service.functions.invoke('platform-notifications',{body:{operation:'emit',event:{eventType:'reservations.public_registration.submitted',moduleKey:'reservations',resourceType:'public_registration_request',resourceId:String(result.data.reference||''),title:'طلب تسجيل جديد',body:'وصل طلب تسجيل جديد ويحتاج للمراجعة.',targetUrl:'./#reservations',dedupeKey:'public-registration:'+publicId+':'+operationId}}});if(emitted.error)console.error(JSON.stringify({code:'PLATFORM_NOTIFICATION_EMIT_FAILED',timestamp:new Date().toISOString()}));}catch(_notificationError){console.error(JSON.stringify({code:'PLATFORM_NOTIFICATION_EMIT_FAILED',timestamp:new Date().toISOString()}));}}
  }
  if(result.error)throw result.error;
  return json(200,{ok:true,data:result.data});
 }catch(error){const e=safe(error);console.error(JSON.stringify({code:e.code,status:e.status,timestamp:new Date().toISOString()}));return json(e.status,{ok:false,error:{code:e.code}});}
});
