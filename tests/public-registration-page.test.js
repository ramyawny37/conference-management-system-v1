'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const vm=require('node:vm');
const html=fs.readFileSync('public-registration.html','utf8');
const js=fs.readFileSync('public-registration.js','utf8');

test('public registration script is valid executable JavaScript',()=>{
  assert.doesNotThrow(()=>new vm.Script(js,{filename:'public-registration.js'}));
});

test('public experience carries the participant-facing mission identity and event journey',()=>{
  assert.match(html,/إرسالية اصنع فرق/);
  assert.match(html,/لِوَقْتٍ مِثْلِ هَذَا/);
  assert.doesNotMatch(html,/نظام إدارة المؤتمرات/);
  assert.match(js,/أهلاً بيك في بيتك/);
  assert.match(js,/بياناتك/);
  assert.match(js,/الأسرة/);
  assert.match(js,/الاشتراك/);
  assert.match(js,/المراجعة/);
  assert.match(js,/e\.name/);
  assert.match(js,/e\.startDate/);
  assert.match(js,/e\.location/);
});

test('public experience uses a real four-step journey without changing the canonical family submission',()=>{
 assert.match(js,/var currentStep=1/); assert.match(js,/data-step-panel="1"/); assert.match(js,/data-step-panel="2"/); assert.match(js,/data-step-panel="3"/); assert.match(js,/data-step-panel="4"/); assert.match(js,/function validateStep\(n\)/); assert.match(js,/function renderBookingStep\(\)/); assert.match(js,/data-booking-type/); assert.match(js,/setStep\(currentStep\+1\)/); assert.match(js,/setStep\(currentStep-1\)/); assert.match(js,/call\('submit_family'/);
});

test('step validation focuses the first incomplete field with a useful inline message',()=>{
  assert.match(js,/function firstProfileIssue\(m,i\)/);
  assert.match(js,/function firstStepIssue\(n\)/);
  assert.match(js,/function focusIssue\(issue,step\)/);
  assert.match(js,/من فضلك أكمل/);
  assert.match(js,/scrollIntoView\(\{behavior:'smooth',block:'center'\}\)/);
  assert.match(js,/setStep\(step,\{scroll:false\}\)/);
  assert.match(js,/aria-invalid/);
  const nextStepBody=js.slice(js.indexOf('function nextStep()'),js.indexOf('function renderBookingStep()'));
  assert.doesNotMatch(nextStepBody,/errorMessage\(code\)/);
});

test('mobile step navigation does not scroll on initial render and native selects commit on change',()=>{
  assert.match(js,/function setStep\(n,options\)/);
  assert.match(js,/options&&options\.scroll/);
  assert.match(js,/setStep\(1,\{scroll:false\}\)/);
  assert.match(js,/el\.tagName==='SELECT'\)el\.blur\(\)/);
  assert.match(js,/el\.blur\(\);var m=members\.find/);
});

test('previous-request recovery stays visually secondary and closed by default',()=>{
  assert.match(js,/<details id="requestTrackingPanel"/);
  assert.match(js,/متابعة أو استرجاع طلب/);
  assert.doesNotMatch(js,/<details id="requestTrackingPanel"[^>]* open/);
});

test('dependent child policy is explicit wherever the family is reviewed',()=>{
  assert.match(js,/طفل مرافق بدون اشتراك — من عمر يوم حتى 6 سنوات، لا يشمل سريرًا أو وجبات/);
  assert.match(js,/dependent-child-notice/);
  assert.match(js,/بدون اشتراك، بدون سرير أو وجبات \(من يوم حتى 6 سنوات\)/);
});

test('technical public errors are localized instead of exposing backend codes',()=>{
  assert.match(js,/PUBLIC_REGISTRATION_MEMBER_IDENTITY_REQUIRED:'أكمل البيانات الأساسية المطلوبة لكل فرد.'/);
  assert.match(js,/PUBLIC_REGISTRATION_BOOKING_TYPE_REQUIRED:'اختر نوع الاشتراك لكل فرد له حجز مستقل.'/);
  assert.match(js,/\^\[A-Z0-9_\]\+\$/);
  assert.match(js,/حدث خطأ أثناء تنفيذ الطلب/);
});

test('public page is isolated from authenticated platform shell',()=>{
  assert.match(html,/public-registration\.js/);
  assert.doesNotMatch(html,/script\.js|reservations-module\.js|device-session/);
});

test('public page uses the one family-capable submission route',()=>{
  assert.match(js,/call\('event'/);
  assert.match(js,/call\('submit_family'/);
  assert.match(js,/call\('status'/);
  assert.doesNotMatch(js,/call\('submit'/);
  assert.match(js,/SUPABASE_RUNTIME_CONFIG/);
  assert.match(js,/\/functions\/v1\/public-registration/);
  assert.doesNotMatch(js,/\.from\(|reservations\.bookings|platform\.people/);
});

test('family UX is progressive and every child selects a preceding guardian',()=>{
  assert.match(js,/إضافة فرد من العائلة/);
  assert.match(js,/data-add="adult"/);
  assert.match(js,/data-add="child_paid"/);
  assert.match(js,/data-add="child_dependent"/);
  assert.match(js,/child_paid/);
  assert.match(js,/child_dependent/);
  assert.match(js,/guardians=members\.slice\(0,i\)/);
  assert.match(js,/data-f="guardianMemberKey"/);
  assert.match(js,/m\.role\.indexOf\('child_'\)===0&&!m\.guardianMemberKey/);
});

test('family summary uses canonical event booking type prices and dependent children are free',()=>{
  assert.match(js,/function familySummary\(\)/);
  assert.match(js,/eventData\.bookingTypes/);
  assert.match(js,/t&&t\.price/);
  assert.match(js,/طفل مرافق — بدون اشتراك، بدون سرير أو وجبات \(من يوم حتى 6 سنوات\)/);
  assert.match(js,/الإجمالي/);
});

test('public share URL stays stable while tracking is kept locally and recovery remains available',()=>{
  assert.doesNotMatch(js,/searchParams\.set\('track'/);
  assert.match(js,/localStorage\.setItem\(trackingKey\(\),value\)/);
  assert.match(js,/trackingSecret:tracking/);
  assert.match(js,/call\('recover'/);
});

test('child inheritance synchronizes the current guardian form values before copying shared context',()=>{
  assert.match(js,/function syncMemberCard\(card\)/);
  assert.match(js,/guardianCard=document\.querySelector/);
  assert.match(js,/if\(guardianCard\)syncMemberCard\(guardianCard\)/);
  assert.match(js,/\['church','governorate','cityOrVillage','serviceSector','serviceSectorOther'\]/);
});

test('device-local tracking keeps multiple request capabilities without storing registration PII',()=>{
  assert.match(js,/public-registration-history:/);
  assert.match(js,/history\.unshift\(\{reference:reference,trackingSecret:value\}\)/);
  assert.match(js,/history\.slice\(0,8\)/);
  assert.match(js,/data-saved-request/);
  assert.doesNotMatch(js,/history\.unshift\(\{[^}]*phone|history\.unshift\(\{[^}]*dateOfBirth|history\.unshift\(\{[^}]*fullName/);
});

test('tracking page renders only server-projected optional financial and accommodation fields',()=>{
  assert.match(js,/s\.financial/);
  assert.match(js,/s\.accommodation/);
  assert.match(js,/لم يتم تخصيص غرفة بعد/);
});

test('tracking page identifies the request owner without exposing primary-booking internals',()=>{
  assert.match(js,/طلب التسجيل باسم/);
  assert.match(js,/x\.role==='primary'/);
  assert.match(js,/أفراد الطلب/);
  assert.match(js,/x\.role!=='primary'/);
  const statusBody=js.slice(js.indexOf('async function showStatus()'),js.indexOf('function trackingKey()'));
  assert.doesNotMatch(statusBody,/رقم الحجز الأساسي/);
  assert.doesNotMatch(statusBody,/المسجل الأساسي/);
});


test('tracking and new-registration actions remain structurally separated',()=>{
  assert.match(js,/id="requestTrackingPanel"/);
  assert.match(js,/id="savedRequestsHost"/);
  assert.match(js,/طلب تسجيل جديد/);
  assert.match(js,/savedHost=document\.getElementById\('savedRequestsHost'\)/);
  assert.doesNotMatch(js,/var actions=document\.querySelector\('\.actions'\).*saved-request/s);
  assert.match(js,/<details class="request-recovery">/);
});


test('service sector UI matches canonical submission contract',()=>{
  assert.match(js,/قطاع الخدمة<\/label><select data-f="serviceSector" required>/);
  assert.doesNotMatch(js,/قطاع الخدمة \*/);
  assert.match(js,/PUBLIC_REGISTRATION_SERVICE_SECTOR_INVALID:'اختر قطاع الخدمة/);
  assert.match(js,/otherInput\.required=m\.serviceSector==='other'/);
  assert.match(js,/if\(!m\.serviceSector\|\|\(m\.serviceSector==='other'&&!m\.serviceSectorOther\)\)throw new Error\('PUBLIC_REGISTRATION_SERVICE_SECTOR_INVALID'\)/);
});


test('public registration assets stay cache-coherent and date fields open from the field',()=>{
    assert.match(html,/public-registration\.css\?rev=public-experience-v7/);
  assert.match(html,/public-registration\.js\?rev=public-experience-v7/);
  assert.match(js,/function bindDatePickers\(root\)/);
  assert.match(js,/typeof input\.showPicker==='function'/);
  assert.match(js,/bindDatePickers\(host\)/);
});

test('public registration explains canonical age errors',()=>{const js=fs.readFileSync('public-registration.js','utf8');assert.match(js,/PUBLIC_REGISTRATION_AGE_INVALID/);assert.match(js,/PUBLIC_REGISTRATION_DATE_OF_BIRTH_INVALID/);});


test('governorate is required by UI and frontend before canonical family submission',()=>{
  assert.match(js,/المحافظة<\/label><select data-f="governorate" required>/);
  assert.match(js,/PUBLIC_REGISTRATION_GOVERNORATE_REQUIRED:'اختر المحافظة.'/);
  assert.match(js,/if\(!m\.governorate\)throw new Error\('PUBLIC_REGISTRATION_GOVERNORATE_REQUIRED'\)/);
  assert.match(js,/\['church','governorate','cityOrVillage','serviceSector','serviceSectorOther'\]/);
});

test('server migration makes governorate authoritative and preserves guardian shared context',()=>{
 const migration=fs.readFileSync('supabase/migrations/20261126193000_public_registration_governorate_contract.sql','utf8');
 assert.match(migration,/PUBLIC_REGISTRATION_GOVERNORATE_REQUIRED/);
 assert.match(migration,/char_length\(v_governorate\)>120/);
 assert.match(migration,/PUBLIC_REGISTRATION_GUARDIAN_CONTEXT_MISMATCH/);
 assert.match(migration,/v_guardian_member/);
 assert.doesNotMatch(migration,/participants_governorate_check/);
});

test('submission success reassures applicant and offers status notification without private-link dependency',()=>{assert.match(js,/طلبك وصل إلينا وهو الآن قيد المراجعة/);assert.match(js,/لا تحتاج إلى إعادة التسجيل أو عمل أي إجراء آخر الآن/);assert.match(js,/supportsStatusNotifications/);assert.match(js,/statusNotificationMarkup/);assert.match(js,/أبلغني عند تحديث حالة الطلب/);assert.doesNotMatch(js,/أضف صفحة التسجيل إلى الشاشة الرئيسية/);assert.match(js,/لا تحتاج للاحتفاظ برابط خاص/);assert.match(js,/من جهاز آخر يمكنك استرجاع الطلب بالاسم ورقم الهاتف \/ واتساب وتاريخ الميلاد/);assert.doesNotMatch(js,/احتفظ بهذا الرابط لمتابعة حالة الطلب/);});


test('accepted tracking extends the same family request with independently reviewed members',()=>{
  assert.match(js,/إضافة فرد للعائلة/);
  assert.match(js,/يمكنك الرجوع في أي وقت لإضافة طفل أو فرد من العائلة إلى طلبك/);
  assert.match(js,/call\('add_family_member'/);
  assert.match(js,/trackingSecret:tracking/);
  assert.match(js,/memberReviewLabel/);
  assert.match(js,/x\.reviewState==='approved'/);
});


test('other service sector explains explicit no-service value',()=>{
  assert.match(js,/إذا كنت تخدم في خدمة معينة اكتب اسمها، وإذا لم توجد خدمة اكتب «لا يوجد»/);
  assert.match(js,/placeholder="اكتب الخدمة، وإذا لم توجد خدمة اكتب: لا يوجد"/);
});
