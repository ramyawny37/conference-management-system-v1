import { createClient } from '@supabase/supabase-js';

const ORIGIN='https://ramyawny37.github.io';
const cors={'Access-Control-Allow-Headers':'content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Origin':ORIGIN,'Vary':'Origin'};
const operations=new Set(['event','submit_family','add_family_member','status','recover','push_config','subscribe_push','unsubscribe_push']);
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
  const serviceKey=JSON.parse(required('SUPABASE_SECRET_KEYS'))['default'];if(!serviceKey)throw new Error('PUBLIC_REGISTRATION_SERVER_CONFIGURATION');const serviceUrl=required('SUPABASE_URL');const service=createClient(serviceUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  let result;
  if(operation==='push_config'){if(!exact(args,[]))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');result={data:{vapidPublicKey:required('PLATFORM_WEB_PUSH_VAPID_PUBLIC_KEY')},error:null};
  }else if(operation==='event'){
    if(!exact(args,['publicId']))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
    result=await service.rpc('public_registration_gateway',{p_operation:'event',p_args:{publicId:uuid((args as any).publicId),fingerprintDigest:hex(fingerprint)}});
  }else if(operation==='status'){
    if(!exact(args,['publicId','trackingSecret']))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
    const a=args as any,tracking=bounded(a.trackingSecret,128,true);
    result=await service.rpc('public_registration_gateway',{p_operation:'status_family',p_args:{publicId:uuid(a.publicId),trackingSecretDigest:hex(await hmac(secret,'track:'+tracking)),fingerprintDigest:hex(fingerprint)}});
  }else if(operation==='recover'){
    if(!exact(args,['dateOfBirth','fullName','phone','publicId']))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
    const a=args as any,publicId=uuid(a.publicId),fullName=bounded(a.fullName,200,true),phone=bounded(a.phone,20,true),dateOfBirth=bounded(a.dateOfBirth,10,true);
    const recoveryBytes=crypto.getRandomValues(new Uint8Array(32)),trackingSecret=b64url(recoveryBytes);
    result=await service.rpc('public_registration_gateway',{p_operation:'recover_family',p_args:{publicId,fullName,phone,dateOfBirth,newTrackingSecretDigest:hex(await hmac(secret,'track:'+trackingSecret)),fingerprintDigest:hex(fingerprint)}});
    if(!result.error)result={...result,data:{...result.data,trackingSecret}};
  }else if(operation==='subscribe_push'){
    if(!exact(args,['auth','endpoint','p256dh','publicId','trackingSecret','userAgent']))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');const a=args as any,tracking=bounded(a.trackingSecret,128,true);result=await service.rpc('public_registration_gateway',{p_operation:'upsert_push_subscription',p_args:{publicId:uuid(a.publicId),trackingSecretDigest:hex(await hmac(secret,'track:'+tracking)),endpoint:bounded(a.endpoint,4096,true),p256dh:bounded(a.p256dh,512,true),auth:bounded(a.auth,256,true),userAgent:bounded(a.userAgent,512)}});
  }else if(operation==='unsubscribe_push'){
    if(!exact(args,['endpoint','publicId','trackingSecret']))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');const a=args as any,tracking=bounded(a.trackingSecret,128,true);result=await service.rpc('public_registration_gateway',{p_operation:'disable_push_subscription',p_args:{publicId:uuid(a.publicId),trackingSecretDigest:hex(await hmac(secret,'track:'+tracking)),endpoint:bounded(a.endpoint,4096,true)}});
  }else if(operation==='add_family_member'){
    if(!exact(args,['member','operationId','publicId','trackingSecret']))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
    const a=args as any,publicId=uuid(a.publicId),operationId=uuid(a.operationId),tracking=bounded(a.trackingSecret,128,true),member=a.member;
    const keys=['bookingTypeId','church','cityOrVillage','dateOfBirth','fullName','gender','governorate','guardianMemberKey','memberKey','notes','phone','role','serviceSector','serviceSectorOther'];
    if(!exact(member,keys))throw new Error('PUBLIC_REGISTRATION_MEMBER_SHAPE_INVALID');
    const normalized={memberKey:uuid(member.memberKey),role:bounded(member.role,20,true),guardianMemberKey:member.guardianMemberKey===null?null:uuid(member.guardianMemberKey),bookingTypeId:member.bookingTypeId===null?null:uuid(member.bookingTypeId),fullName:bounded(member.fullName,200,true),phone:bounded(member.phone,20),gender:member.gender===null?null:bounded(member.gender,12),dateOfBirth:bounded(member.dateOfBirth,10,true),church:bounded(member.church,200),governorate:bounded(member.governorate,120),cityOrVillage:bounded(member.cityOrVillage,160),serviceSector:bounded(member.serviceSector,160),serviceSectorOther:member.serviceSectorOther===null?null:bounded(member.serviceSectorOther,200),notes:member.notes===null?null:bounded(member.notes,4000)};
    result=await service.rpc('public_registration_gateway',{p_operation:'add_family_member',p_args:{publicId,operationId,trackingSecretDigest:hex(await hmac(secret,'track:'+tracking)),fingerprintDigest:hex(fingerprint),member:normalized}});
  }else if(operation==='submit_family'){
    if(!exact(args,['members','operationId','publicId'])||!Array.isArray((args as any).members))throw new Error('PUBLIC_REGISTRATION_ARGUMENT_INVALID');
    const a=args as any,publicId=uuid(a.publicId),operationId=uuid(a.operationId);
    if(a.members.length<1||a.members.length>12)throw new Error('PUBLIC_REGISTRATION_FAMILY_SIZE_INVALID');
    const members=a.members.map((member:any,index:number)=>{
      const keys=['bookingTypeId','church','cityOrVillage','dateOfBirth','fullName','gender','governorate','guardianMemberKey','memberKey','notes','phone','role','serviceSector','serviceSectorOther'];
      if(!exact(member,keys))throw new Error('PUBLIC_REGISTRATION_MEMBER_SHAPE_INVALID');
      return {memberKey:uuid(member.memberKey),role:bounded(member.role,20,true),guardianMemberKey:member.guardianMemberKey===null?null:uuid(member.guardianMemberKey),bookingTypeId:member.bookingTypeId===null?null:uuid(member.bookingTypeId),fullName:bounded(member.fullName,200,true),phone:bounded(member.phone,20),gender:member.gender===null?null:bounded(member.gender,12),dateOfBirth:bounded(member.dateOfBirth,10,true),church:bounded(member.church,200),governorate:bounded(member.governorate,120),cityOrVillage:bounded(member.cityOrVillage,160),serviceSector:bounded(member.serviceSector,160),serviceSectorOther:member.serviceSectorOther===null?null:bounded(member.serviceSectorOther,200),notes:member.notes===null?null:bounded(member.notes,4000)};
    });
    const trackingBytes=await hmac(secret,'tracking:'+publicId+':'+operationId),trackingSecret=b64url(trackingBytes);
    result=await service.rpc('public_registration_gateway',{p_operation:'submit_family',p_args:{publicId,submitOperationId:operationId,trackingSecretDigest:hex(await hmac(secret,'track:'+trackingSecret)),fingerprintDigest:hex(fingerprint),members}});
    if(!result.error){const eventId=uuid(result.data.eventId),publicData={...result.data,trackingSecret};delete publicData.eventId;result={...result,data:publicData};try{const flushed=await fetch(serviceUrl+'/functions/v1/platform-notifications',{method:'POST',headers:{'Content-Type':'application/json','apikey':serviceKey},body:JSON.stringify({operation:'flush'})});if(!flushed.ok)console.error(JSON.stringify({code:'PLATFORM_NOTIFICATION_PUSH_FLUSH_FAILED',timestamp:new Date().toISOString()}));}catch(_notificationError){console.error(JSON.stringify({code:'PLATFORM_NOTIFICATION_PUSH_FLUSH_FAILED',timestamp:new Date().toISOString()}));}}
  }
  if(result.error)throw result.error;
  return json(200,{ok:true,data:result.data});
 }catch(error){const e=safe(error);console.error(JSON.stringify({code:e.code,status:e.status,timestamp:new Date().toISOString()}));return json(e.status,{ok:false,error:{code:e.code}});}
});
