(function(global){
  'use strict';

  var MODULE_ID='reservations-prototype';
  var root=null;
  var listeners=[];
  var mockBookings=Object.freeze([
    Object.freeze({id:'RV-1026',name:'أحمد محمد',phone:'010 2456 8891',type:'غرفة مزدوجة',date:'15 سبتمبر 2026',status:'confirmed',statusLabel:'مؤكد',attendance:'attended',attendanceLabel:'حضر',amount:'2,500 ج.م'}),
    Object.freeze({id:'RV-1025',name:'سارة علي',phone:'011 7832 1140',type:'غرفة فردية',date:'15 سبتمبر 2026',status:'pending',statusLabel:'قيد التأكيد',attendance:'pending',attendanceLabel:'لم يسجل',amount:'1,800 ج.م'}),
    Object.freeze({id:'RV-1024',name:'خالد نبيل',phone:'012 9941 0223',type:'بدون غرفة',date:'14 سبتمبر 2026',status:'paid',statusLabel:'مدفوع',attendance:'attended',attendanceLabel:'حضر',amount:'1,200 ج.م'}),
    Object.freeze({id:'RV-1023',name:'منى يوسف',phone:'010 6678 2031',type:'غرفة ثلاثية',date:'14 سبتمبر 2026',status:'cancelled',statusLabel:'ملغي',attendance:'absent',attendanceLabel:'غائب',amount:'2,700 ج.م'}),
    Object.freeze({id:'RV-1022',name:'إياد حياة',phone:'015 4002 1862',type:'بدون غرفة',date:'14 سبتمبر 2026',status:'confirmed',statusLabel:'مؤكد',attendance:'corrected',attendanceLabel:'تم التصحيح',amount:'1,200 ج.م'}),
    Object.freeze({id:'RV-1021',name:'مريم فؤاد',phone:'010 3320 6714',type:'غرفة مزدوجة',date:'13 سبتمبر 2026',status:'waiting',statusLabel:'قائمة انتظار',attendance:'pending',attendanceLabel:'لم يسجل',amount:'2,500 ج.م'})
  ]);

  function bookingRows(items){
    return items.map(function(item){
      return '<tr data-booking-row="'+item.id+'">'+
        '<td><strong class="rvp-reference">'+item.id+'</strong></td>'+
        '<td><span class="rvp-person"><span class="rvp-avatar">'+item.name.charAt(0)+'</span><span><strong>'+item.name+'</strong><small>'+item.phone+'</small></span></span></td>'+
        '<td>'+item.type+'</td><td>'+item.date+'</td><td>'+item.amount+'</td>'+
        '<td><span class="rvp-badge rvp-badge--'+item.status+'">'+item.statusLabel+'</span></td>'+
        '<td><span class="rvp-attendance rvp-attendance--'+item.attendance+'"><i></i>'+item.attendanceLabel+'</span></td>'+
        '<td><button class="rvp-icon-button" type="button" data-open-details="'+item.id+'" aria-label="عرض تفاصيل '+item.name+'">•••</button></td></tr>';
    }).join('');
  }

  function mobileCards(items){
    return items.map(function(item){
      return '<article class="rvp-booking-card" data-booking-card="'+item.id+'"><header><span class="rvp-person"><span class="rvp-avatar">'+item.name.charAt(0)+'</span><span><strong>'+item.name+'</strong><small>'+item.id+'</small></span></span><span class="rvp-badge rvp-badge--'+item.status+'">'+item.statusLabel+'</span></header><dl><div><dt>نوع الحجز</dt><dd>'+item.type+'</dd></div><div><dt>التاريخ</dt><dd>'+item.date+'</dd></div><div><dt>الحضور</dt><dd>'+item.attendanceLabel+'</dd></div><div><dt>القيمة</dt><dd>'+item.amount+'</dd></div></dl><button type="button" class="rvp-button rvp-button--soft" data-open-details="'+item.id+'">عرض التفاصيل</button></article>';
    }).join('');
  }

  function shell(){
    return '<section class="rvp-workspace" data-reservations-prototype-root data-prototype-state="populated">'+
      '<div class="rvp-context"><div><span class="rvp-context__eyebrow">نموذج بصري · بيانات تجريبية</span><h1>إدارة الحجوزات</h1></div><div class="rvp-context__actions"><a class="rvp-button rvp-button--ghost" href="#/reservations">العودة للنظام الفعلي</a><button class="rvp-button rvp-button--primary" type="button" data-open-form>+ حجز جديد</button></div></div>'+
      '<div class="rvp-dashboard">'+
        '<section class="rvp-hero"><div class="rvp-hero__welcome"><span>مرحبًا بك</span><h2>مركز تشغيل الحجوزات</h2><p>نظرة يومية واضحة على التسجيل والسداد والحضور في مكان واحد.</p></div><div class="rvp-event"><div class="rvp-event__art">2026</div><div><span class="rvp-badge rvp-badge--active">نشط</span><h3>مؤتمر الشباب 2026</h3><p>15–20 سبتمبر · قاعة النيل</p><button type="button" class="rvp-button rvp-button--primary">فتح المؤتمر ←</button></div></div><blockquote>« تشغيل أسرع · متابعة أوضح · تجربة أفضل »</blockquote></section>'+
        '<section class="rvp-metrics" aria-label="ملخص الحجوزات">'+
          '<article><span class="rvp-metric-icon rvp-tone-blue">♙</span><div><strong>337</strong><span>إجمالي الحجوزات</span><small class="rvp-up">↑ 12%</small></div></article>'+
          '<article><span class="rvp-metric-icon rvp-tone-green">✓</span><div><strong>268</strong><span>حجوزات مؤكدة</span><small class="rvp-up">↑ 8%</small></div></article>'+
          '<article><span class="rvp-metric-icon rvp-tone-orange">◷</span><div><strong>69</strong><span>قيد التأكيد</span><small class="rvp-down">↓ 5%</small></div></article>'+
          '<article><span class="rvp-metric-icon rvp-tone-red">×</span><div><strong>12</strong><span>ملغاة</span><small class="rvp-down">↓ 2%</small></div></article>'+
          '<article><span class="rvp-metric-icon rvp-tone-purple">▣</span><div><strong>156</strong><span>تم الحضور</span><small>من 182 متوقعًا</small></div></article>'+
          '<article><span class="rvp-metric-icon rvp-tone-cyan">◉</span><div><strong>26</strong><span>لم يسجل الحضور</span><small>تحتاج متابعة</small></div></article>'+
          '<article><span class="rvp-metric-icon rvp-tone-gold">▤</span><div><strong>493,450</strong><span>إجمالي المدفوعات</span><small class="rvp-up">↑ 18%</small></div></article>'+
        '</section>'+
        '<nav class="rvp-actions" aria-label="إجراءات سريعة"><button type="button" data-open-form><span class="rvp-tone-blue">＋</span>تسجيل حجز</button><button type="button"><span class="rvp-tone-green">✓</span>تسجيل حضور</button><button type="button"><span class="rvp-tone-purple">▦</span>استلام سداد</button><button type="button"><span class="rvp-tone-orange">▤</span>إصدار إيصال</button><button type="button"><span class="rvp-tone-cyan">⌕</span>البحث السريع</button><button type="button"><span>•••</span>المزيد</button></nav>'+
        '<section class="rvp-insights">'+
          '<article class="rvp-panel rvp-alerts"><header><h3>إجراءات عاجلة</h3><span>6</span></header><ul><li><i class="rvp-dot rvp-red"></i><span>حجوزات تحتاج تأكيد</span><strong>4</strong></li><li><i class="rvp-dot rvp-orange"></i><span>مدفوعات غير مكتملة</span><strong>2</strong></li><li><i class="rvp-dot rvp-purple"></i><span>تصحيحات حضور</span><strong>1</strong></li></ul><button type="button" class="rvp-link">عرض كل التنبيهات ←</button></article>'+
          '<article class="rvp-panel"><header><h3>معدل الإشغال</h3><span>الغرف</span></header><div class="rvp-ring" style="--progress:68%;--ring:#0a6cff"><strong>68%</strong><small>من الإجمالي</small></div><div class="rvp-legend"><span><i class="rvp-blue"></i>محجوزة <b>156</b></span><span><i class="rvp-cyan"></i>متاحة <b>74</b></span><span><i class="rvp-gray"></i>صيانة <b>8</b></span></div></article>'+
          '<article class="rvp-panel"><header><h3>حالة التسجيل</h3><span>اليوم</span></header><div class="rvp-ring" style="--progress:88%;--ring:#00c853"><strong>88%</strong><small>مكتمل</small></div><div class="rvp-legend"><span><i class="rvp-green"></i>مؤكد <b>268</b></span><span><i class="rvp-orange"></i>قيد التأكيد <b>69</b></span><span><i class="rvp-red"></i>مرفوض <b>12</b></span></div></article>'+
          '<article class="rvp-panel"><header><h3>حالة السداد</h3><span>ج.م</span></header><div class="rvp-ring" style="--progress:76%;--ring:#00bcd4"><strong>76%</strong><small>تم تحصيلها</small></div><div class="rvp-legend"><span><i class="rvp-cyan"></i>مدفوع <b>493,450</b></span><span><i class="rvp-blue"></i>متبقي <b>155,200</b></span><span><i class="rvp-orange"></i>متأخر <b>28,600</b></span></div></article>'+
          '<article class="rvp-panel rvp-chart"><header><h3>الحضور خلال الأيام</h3><button type="button">هذا الأسبوع⌄</button></header><div class="rvp-bars"><span style="--height:38%"><b>120</b><i></i><small>السبت</small></span><span style="--height:72%"><b>280</b><i></i><small>الأربعاء</small></span><span style="--height:88%"><b>310</b><i></i><small>الخميس</small></span><span style="--height:68%"><b>275</b><i></i><small>الجمعة</small></span><span style="--height:54%"><b>200</b><i></i><small>الثلاثاء</small></span></div></article>'+
        '</section>'+
        '<section class="rvp-operations">'+
          '<article class="rvp-panel rvp-list-panel"><header class="rvp-list-heading"><div><h3>قائمة الحجوزات</h3><p>متابعة عمليات الحجز والسداد والحضور</p></div><div class="rvp-view-switch" aria-label="حالة العرض"><button type="button" data-view-state="populated" class="is-active">ممتلئ</button><button type="button" data-view-state="loading">تحميل</button><button type="button" data-view-state="empty">فارغ</button><button type="button" data-view-state="error">خطأ</button></div></header>'+filterBar()+'<div class="rvp-table-wrap"><table><thead><tr><th>المرجع</th><th>الاسم وبيانات الاتصال</th><th>نوع الحجز</th><th>التاريخ</th><th>القيمة</th><th>الحالة</th><th>الحضور</th><th>إجراء</th></tr></thead><tbody data-booking-rows>'+bookingRows(mockBookings)+'</tbody></table></div><div class="rvp-mobile-list" data-mobile-bookings>'+mobileCards(mockBookings)+'</div>'+stateSurfaces()+'<footer><span>عرض 1–6 من 337 حجزًا</span><div><button type="button" disabled>السابق</button><button type="button" class="is-active">1</button><button type="button">2</button><button type="button">3</button><button type="button">التالي</button></div></footer></article>'+
          '<aside class="rvp-side-stack"><article class="rvp-panel rvp-schedule"><header><h3>جدول اليوم</h3><span>الأحد 15 سبتمبر</span></header><ol><li><time>08:00</time><span>استقبال المشاركين</span></li><li><time>10:00</time><span>الجلسة الافتتاحية</span></li><li><time>12:30</time><span>استراحة وغداء</span></li><li><time>14:00</time><span>ورش العمل</span></li><li><time>18:00</time><span>المساء الترفيهي</span></li></ol></article><article class="rvp-panel rvp-tools"><header><h3>أدوات سريعة</h3></header><div><button type="button">طباعة قائمة</button><button type="button">تصدير تقرير</button><button type="button">استيراد بيانات</button><button type="button">إرسال رسالة</button></div></article></aside>'+
        '</section>'+
      '</div>'+detailsDrawer()+formDialog()+'</section>';
  }

  function filterBar(){
    return '<div class="rvp-filters"><label class="rvp-search"><span>⌕</span><input type="search" data-search placeholder="ابحث بالاسم أو رقم الحجز أو الهاتف..." aria-label="البحث في الحجوزات"></label><select data-status-filter aria-label="تصفية حسب الحالة"><option value="">كل الحالات</option><option value="confirmed">مؤكد</option><option value="pending">قيد التأكيد</option><option value="waiting">قائمة انتظار</option><option value="cancelled">ملغي</option></select><select data-type-filter aria-label="تصفية حسب نوع الحجز"><option value="">كل أنواع الحجز</option><option>غرفة مزدوجة</option><option>غرفة فردية</option><option>غرفة ثلاثية</option><option>بدون غرفة</option></select><button class="rvp-button rvp-button--soft" type="button" data-reset-filters>مسح الفلاتر</button><span class="rvp-active-filter" data-filter-summary hidden></span></div>';
  }

  function stateSurfaces(){
    return '<div class="rvp-state rvp-state--loading" data-state-surface="loading"><span class="rvp-spinner"></span><strong>جارٍ تحميل الحجوزات...</strong><small>يتم تجهيز أحدث بيانات التشغيل</small></div><div class="rvp-state rvp-state--empty" data-state-surface="empty"><span>▤</span><strong>لا توجد حجوزات بعد</strong><small>ابدأ بإضافة أول حجز لهذا المؤتمر.</small><button type="button" class="rvp-button rvp-button--primary" data-open-form>إضافة حجز</button></div><div class="rvp-state rvp-state--no-results" data-state-surface="no-results"><span>⌕</span><strong>لا توجد نتائج مطابقة</strong><small>غيّر عبارة البحث أو امسح الفلاتر النشطة.</small><button type="button" class="rvp-button rvp-button--soft" data-reset-filters>مسح الفلاتر</button></div><div class="rvp-state rvp-state--error" data-state-surface="error" role="alert"><span>!</span><strong>تعذر تحميل الحجوزات</strong><small>هذه حالة عرض تجريبية ولا يوجد اتصال بالخادم.</small><button type="button" class="rvp-button rvp-button--soft" data-view-state="populated">إعادة المحاولة</button></div>';
  }

  function detailsDrawer(){
    return '<div class="rvp-overlay" data-details-overlay hidden><aside class="rvp-drawer" role="dialog" aria-modal="true" aria-labelledby="rvp-details-title"><header><div><span class="rvp-context__eyebrow">تفاصيل الحجز</span><h2 id="rvp-details-title">RV-1026</h2></div><button type="button" class="rvp-close" data-close-details aria-label="إغلاق">×</button></header><div class="rvp-drawer__body"><section class="rvp-profile"><span class="rvp-avatar rvp-avatar--large">أ</span><div><h3 data-detail-name>أحمد محمد</h3><p data-detail-phone>010 2456 8891</p></div><span class="rvp-badge rvp-badge--confirmed">مؤكد</span></section><section class="rvp-detail-grid"><div><span>نوع الحجز</span><strong data-detail-type>غرفة مزدوجة</strong></div><div><span>التاريخ</span><strong data-detail-date>15 سبتمبر 2026</strong></div><div><span>القيمة</span><strong data-detail-amount>2,500 ج.م</strong></div><div><span>حالة السداد</span><strong>مدفوع جزئيًا</strong></div></section><section class="rvp-detail-section"><h3>بيانات التواصل</h3><dl><div><dt>رقم الهاتف</dt><dd data-detail-contact>010 2456 8891</dd></div><div><dt>البريد الإلكتروني</dt><dd>ahmed@example.test</dd></div><div><dt>المحافظة</dt><dd>القاهرة</dd></div></dl></section><section class="rvp-detail-section"><div class="rvp-section-title"><h3>الحضور</h3><span class="rvp-badge rvp-badge--paid">تم الحضور</span></div><div class="rvp-attendance-box"><label><input type="radio" name="mock-attendance" checked> حضر</label><label><input type="radio" name="mock-attendance"> غائب</label><label>تاريخ الحضور<input type="date" value="2026-09-15"></label><label>ملاحظات<textarea rows="2">تم تسجيل الحضور عند البوابة الرئيسية.</textarea></label><button type="button" class="rvp-button rvp-button--soft" data-mock-correction>تسجيل تصحيح حضور</button><small data-correction-note hidden>تم عرض حالة التصحيح محليًا فقط.</small></div></section><section class="rvp-detail-section"><h3>ملاحظات الحجز</h3><p>يفضل غرفة قريبة من المصعد. تم تأكيد بيانات الوصول هاتفيًا.</p></section></div><footer><button type="button" class="rvp-button rvp-button--ghost" data-close-details>إغلاق</button><button type="button" class="rvp-button rvp-button--primary" data-open-form>تعديل الحجز</button></footer></aside></div>';
  }

  function formDialog(){
    return '<div class="rvp-overlay" data-form-overlay hidden><section class="rvp-modal" role="dialog" aria-modal="true" aria-labelledby="rvp-form-title" data-form-mode="default"><header><div><span class="rvp-context__eyebrow">تدفق تجريبي</span><h2 id="rvp-form-title">حجز جديد</h2></div><button type="button" class="rvp-close" data-close-form aria-label="إغلاق">×</button></header><div class="rvp-form-body"><div class="rvp-stepper"><span class="is-active">1 بيانات المشارك</span><span>2 تفاصيل الحجز</span><span>3 المراجعة</span></div><section class="rvp-form-section"><h3>بيانات المشارك</h3><div class="rvp-form-grid"><label>الاسم بالكامل <b>*</b><input value="مينا سامح" data-required-field></label><label>رقم الهاتف <b>*</b><input value="010 1234 5678"></label><label>البريد الإلكتروني<input type="email" placeholder="name@example.com"></label><label>المحافظة<select><option>القاهرة</option><option>الجيزة</option></select></label></div></section><section class="rvp-form-section"><h3>تفاصيل الحجز</h3><div class="rvp-form-grid"><label>نوع الحجز <b>*</b><select><option>غرفة مزدوجة</option><option>غرفة فردية</option><option>بدون غرفة</option></select></label><label>تاريخ الوصول<input type="date" value="2026-09-15"></label><label>تاريخ المغادرة<input type="date" value="2026-09-20"></label><label class="rvp-field--wide">ملاحظات<textarea rows="3" placeholder="أضف ملاحظات تشغيلية..."></textarea></label></div></section><div class="rvp-form-feedback rvp-form-feedback--validation" role="alert">يرجى استكمال الحقول المطلوبة قبل الحفظ.</div><div class="rvp-form-feedback rvp-form-feedback--saving" role="status"><span class="rvp-spinner"></span> جارٍ حفظ النموذج التجريبي...</div><div class="rvp-form-feedback rvp-form-feedback--success" role="status">✓ تم حفظ النموذج التجريبي بنجاح.</div><div class="rvp-form-feedback rvp-form-feedback--error" role="alert">تعذر الحفظ في حالة العرض التجريبية.</div><div class="rvp-form-state-controls"><span>معاينة الحالة:</span><button type="button" data-form-state="validation">تحقق</button><button type="button" data-form-state="saving">حفظ</button><button type="button" data-form-state="success">نجاح</button><button type="button" data-form-state="error">خطأ</button><button type="button" data-form-state="default">إعادة</button></div></div><footer><button type="button" class="rvp-button rvp-button--ghost" data-close-form>إلغاء</button><button type="button" class="rvp-button rvp-button--primary" data-form-state="saving">حفظ الحجز</button></footer></section></div>';
  }

  function on(target,type,handler){target.addEventListener(type,handler);listeners.push(function(){target.removeEventListener(type,handler);});}
  function setHidden(element,hidden){if(element)element.hidden=hidden;}
  function openDetails(id){
    var booking=mockBookings.find(function(item){return item.id===id;})||mockBookings[0];
    root.querySelector('#rvp-details-title').textContent=booking.id;
    root.querySelector('[data-detail-name]').textContent=booking.name;
    root.querySelector('[data-detail-phone]').textContent=booking.phone;
    root.querySelector('[data-detail-contact]').textContent=booking.phone;
    root.querySelector('[data-detail-type]').textContent=booking.type;
    root.querySelector('[data-detail-date]').textContent=booking.date;
    root.querySelector('[data-detail-amount]').textContent=booking.amount;
    setHidden(root.querySelector('[data-details-overlay]'),false);
  }
  function openForm(){setHidden(root.querySelector('[data-details-overlay]'),true);setHidden(root.querySelector('[data-form-overlay]'),false);}
  function setViewState(state){
    root.querySelector('[data-reservations-prototype-root]').setAttribute('data-prototype-state',state);
    root.querySelectorAll('[data-view-state]').forEach(function(button){button.classList.toggle('is-active',button.getAttribute('data-view-state')===state);});
  }
  function applyFilters(){
    var query=root.querySelector('[data-search]').value.trim().toLowerCase();
    var status=root.querySelector('[data-status-filter]').value;
    var type=root.querySelector('[data-type-filter]').value;
    var matches=mockBookings.filter(function(item){return (!query||(item.name+' '+item.phone+' '+item.id).toLowerCase().includes(query))&&(!status||item.status===status)&&(!type||item.type===type);});
    root.querySelector('[data-booking-rows]').innerHTML=bookingRows(matches);
    root.querySelector('[data-mobile-bookings]').innerHTML=mobileCards(matches);
    var summary=root.querySelector('[data-filter-summary]');
    var active=Boolean(query||status||type);
    summary.textContent=active?'فلاتر نشطة · '+matches.length+' نتيجة':'';
    summary.hidden=!active;
    setViewState(matches.length?'populated':'no-results');
  }
  function resetFilters(){root.querySelector('[data-search]').value='';root.querySelector('[data-status-filter]').value='';root.querySelector('[data-type-filter]').value='';applyFilters();}
  function handleClick(event){
    var trigger=event.target.closest('[data-open-details],[data-close-details],[data-open-form],[data-close-form],[data-view-state],[data-reset-filters],[data-form-state],[data-mock-correction]');
    if(!trigger||!root.contains(trigger))return;
    if(trigger.hasAttribute('data-open-details'))openDetails(trigger.getAttribute('data-open-details'));
    else if(trigger.hasAttribute('data-close-details'))setHidden(root.querySelector('[data-details-overlay]'),true);
    else if(trigger.hasAttribute('data-open-form'))openForm();
    else if(trigger.hasAttribute('data-close-form'))setHidden(root.querySelector('[data-form-overlay]'),true);
    else if(trigger.hasAttribute('data-view-state'))setViewState(trigger.getAttribute('data-view-state'));
    else if(trigger.hasAttribute('data-reset-filters'))resetFilters();
    else if(trigger.hasAttribute('data-form-state'))root.querySelector('.rvp-modal').setAttribute('data-form-mode',trigger.getAttribute('data-form-state'));
    else if(trigger.hasAttribute('data-mock-correction'))setHidden(root.querySelector('[data-correction-note]'),false);
  }
  function handleInput(event){if(event.target&&event.target.matches('[data-search]'))applyFilters();}
  function handleChange(event){if(event.target&&event.target.matches('[data-status-filter],[data-type-filter]'))applyFilters();}
  function mount(context){
    if(!context||!(context.container instanceof global.HTMLElement))throw new Error('PLATFORM_MODULE_CONTAINER_REQUIRED');
    if(root&&root!==context.container)unmount();
    root=context.container;
    root.innerHTML=shell();
    on(root,'click',handleClick);
    on(root,'input',handleInput);
    on(root,'change',handleChange);
    return true;
  }
  function unmount(){listeners.splice(0).forEach(function(remove){remove();});if(root)root.innerHTML='';root=null;return true;}

  var moduleDefinition=Object.freeze({id:MODULE_ID,mount:mount,unmount:unmount,reconcileRoute:function(context){return root?true:mount(context);}});
  if(!global.PlatformIntegration||typeof global.PlatformIntegration.registerModule!=='function')throw new Error('PLATFORM_MODULE_REGISTRY_REQUIRED');
  global.ReservationsVisualPrototype=Object.freeze({mockBookings:mockBookings,module:moduleDefinition});
  global.PlatformIntegration.registerModule(moduleDefinition);
})(window);
