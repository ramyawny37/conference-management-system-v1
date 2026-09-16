(function(global){
'use strict';
var doc=global.document;
if(!doc)return;
var timers=[];
function icon(name){var map={users:'👥',check:'✓',alert:'!',bed:'▣',meal:'♨',money:'▤',search:'⌕',calendar:'▦',note:'▧'};return '<span class="rv3-icon" aria-hidden="true">'+(map[name]||'•')+'</span>';}
function stat(cls,ico,value,label,delta){return '<article class="rv3-stat rv3-'+cls+'">'+icon(ico)+'<div><strong>'+value+'</strong><span>'+label+'</span>'+(delta?'<small>'+delta+'</small>':'')+'</div></article>';}
function action(cls,ico,label){return '<button type="button" class="rv3-action rv3-'+cls+'">'+icon(ico)+'<span>'+label+'</span></button>';}
function ring(title,value,lines,cls){return '<article class="rv3-card rv3-ring-card"><header><h3>'+title+'</h3></header><div class="rv3-card-body"><div class="rv3-ring rv3-'+cls+'" style="--p:'+value+'"><strong>'+value+'%</strong><span>من الإجمالي</span></div><div class="rv3-ring-lines">'+lines+'</div></div></article>';}
function isReservations(){var hash=String(global.location.hash||'');var route='';try{route=global.ApplicationRouting&&global.ApplicationRouting.getLogicalPathname?String(global.ApplicationRouting.getLogicalPathname()||''):'';}catch(_e){}return hash.indexOf('reservations')>=0||route.indexOf('/reservations')===0;}
function template(){return '<main class="rv3-dashboard" data-reservations-reference-v3 aria-label="لوحة الحجوزات الجديدة">\
<section class="rv3-hero">\
 <div class="rv3-welcome"><span>مرحبًا بك</span><h1>منصة الإدارة المتكاملة</h1><p>كل ما تحتاجه لتنظيم وتشغيل الحجوزات في مكان واحد</p></div>\
 <div class="rv3-event"><div class="rv3-event-art">'+icon('calendar')+'</div><div class="rv3-event-copy"><span class="rv3-chip">نشط</span><h2>مؤتمر الشباب 2026</h2><p>15 - 20 سبتمبر 2026 · قاعة النيل - القاهرة</p><button type="button">فتح المؤتمر ←</button></div></div>\
 <div class="rv3-motto">« تنظيم أفضل · خدمة أسرع · تجربة أمتع »</div>\
</section>\
<section class="rv3-stats">'+stat('blue','users','337','إجمالي المشاركين','↑ 12%')+stat('green','check','268','تم تسجيلهم','↑ 8%')+stat('orange','alert','69','قيد التأكيد','↓ 5%')+stat('red','alert','12','معلق / مشكلة','↓ 2%')+stat('purple','bed','156','غرف محجوزة','85%')+stat('cyan','meal','320','وجبات مؤكدة','75%')+stat('gold','money','493,450 ج.م','إجمالي المدفوعات','↑ 18%')+'</section>\
<section class="rv3-actions">'+action('blue','users','تسجيل مشارك')+action('green','bed','حجز غرفة')+action('purple','calendar','تسجيل حضور')+action('orange','money','استلام سداد')+action('sky','search','البحث السريع')+action('plain','note','المزيد')+'</section>\
<section class="rv3-insights">\
 <article class="rv3-card rv3-alerts"><header><h3>إجراءات عاجلة</h3></header><div class="rv3-card-body"><p><b>4</b><span>حجوزات تحتاج تأكيد</span></p><p><b>2</b><span>مدفوعات غير مكتملة</span></p><p><b>3</b><span>طلبات خاصة جديدة</span></p><p><b>1</b><span>مشاكل في الحضور</span></p><p><b>5</b><span>رسائل غير مقروءة</span></p><a>عرض كل التنبيهات ←</a></div></article>\
 '+ring('معدل الإشغال','68','<p><i></i>محجوزة <b>156</b></p><p><i></i>متاحة <b>74</b></p><p><i></i>صيانة <b>8</b></p>','blue')+'\
 '+ring('حالة التسجيل','88','<p><i></i>مؤكد <b>268</b></p><p><i></i>قيد التأكيد <b>69</b></p><p><i></i>مرفوض <b>12</b></p>','green')+'\
 '+ring('حالة السداد','76','<p><i></i>مدفوع <b>493,450</b></p><p><i></i>متبقي <b>155,200</b></p><p><i></i>متأخر <b>28,600</b></p>','cyan')+'\
 <article class="rv3-card rv3-chart-card"><header><h3>الحضور خلال الأيام</h3><button>هذا الأسبوع⌄</button></header><div class="rv3-card-body"><div class="rv3-bars"><span style="--h:38%"><b>120</b><i></i><small>السبت</small></span><span style="--h:72%"><b>280</b><i></i><small>الأربعاء</small></span><span style="--h:88%"><b>310</b><i></i><small>الخميس</small></span><span style="--h:78%"><b>275</b><i></i><small>الجمعة</small></span><span style="--h:58%"><b>200</b><i></i><small>الثلاثاء</small></span></div></div></article>\
</section>\
<section class="rv3-lower">\
 <article class="rv3-card rv3-schedule"><header><h3>جدول اليوم</h3></header><div class="rv3-card-body"><p><b>08:00</b> استقبال المشاركين</p><p><b>10:00</b> الجلسة الافتتاحية</p><p><b>12:30</b> استراحة وغداء</p><p><b>14:00</b> ورش العمل</p><p><b>18:00</b> المساء الترفيهي</p><button>عرض الجدول الكامل ←</button></div></article>\
 <article class="rv3-card rv3-bookings"><div class="rv3-tabs"><b>أحدث الحجوزات</b><span>أحدث التسجيلات</span><span>المدفوعات الأخيرة</span><span>الملاحظات</span><span>المهام</span></div><div class="rv3-table-wrap"><table><thead><tr><th>#</th><th>الاسم</th><th>نوع الحجز</th><th>الحالة</th><th>المبلغ</th><th>تاريخ الحجز</th><th>إجراءات</th></tr></thead><tbody><tr><td>#1026</td><td>أحمد محمد</td><td>غرفة مزدوجة</td><td><em class="ok">مؤكد</em></td><td>2,500 ج.م</td><td>2026-09-15</td><td>•••</td></tr><tr><td>#1025</td><td>سارة علي</td><td>غرفة فردية</td><td><em class="wait">قيد التأكيد</em></td><td>1,800 ج.م</td><td>2026-09-15</td><td>•••</td></tr><tr><td>#1024</td><td>خالد نبيل</td><td>بدون غرفة</td><td><em class="ok">مدفوع</em></td><td>1,200 ج.م</td><td>2026-09-14</td><td>•••</td></tr><tr><td>#1023</td><td>منى يوسف</td><td>غرفة ثلاثية</td><td><em class="bad">معلق</em></td><td>2,700 ج.م</td><td>2026-09-14</td><td>•••</td></tr></tbody></table></div><button class="rv3-more">عرض جميع الحجوزات ←</button></article>\
 <div class="rv3-tools"><article class="rv3-card"><header><h3>بحث سريع</h3></header><div class="rv3-card-body"><label class="rv3-search">'+icon('search')+'<input placeholder="الاسم أو رقم الحجز أو الهاتف ..."></label><div class="rv3-tags"><span>مشارك</span><span>حجز</span><span>دفعة</span><span>غرفة</span></div><button class="rv3-primary">بحث</button></div></article><article class="rv3-card"><header><h3>أدوات سريعة</h3></header><div class="rv3-card-body rv3-tool-grid"><button>طباعة شهادة</button><button>تصدير تقرير</button><button>استيراد بيانات</button><button>إرسال رسالة</button><button>تحويل حجز</button><button>إلغاء حجز</button></div></article></div>\
</section>\
</main>';}
function mount(force){if(!isReservations())return;var workspace=doc.getElementById('reservationsWorkspace');if(!workspace)return;var existing=workspace.querySelector('[data-reservations-reference-v3]');if(existing&&!force)return;workspace.innerHTML=template();workspace.classList.add('reservations-reference-v3-host');}
function schedule(){timers.forEach(global.clearTimeout);timers=[0,80,220,500,900,1500,2400].map(function(ms){return global.setTimeout(function(){mount(ms>=900);},ms);});}
if(doc.readyState==='loading')doc.addEventListener('DOMContentLoaded',schedule);else schedule();
global.addEventListener('load',schedule);
global.addEventListener('hashchange',schedule);
doc.addEventListener('click',function(e){if(e.target&&e.target.closest&&e.target.closest('[data-platform-module="reservations"]'))global.setTimeout(schedule,40);});
})(window);
