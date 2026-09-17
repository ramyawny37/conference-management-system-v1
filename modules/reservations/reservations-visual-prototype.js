(function(global){
  'use strict';

  var MODULE_ID='reservations-prototype';
  var root=null;
  var listeners=[];
  var mockViewModel=Object.freeze({
    context:Object.freeze({title:'مؤتمر الشباب 2026',status:'نشط',period:'15 – 20 سبتمبر 2026',location:'قاعة النيل - القاهرة'}),
    metrics:Object.freeze([
      Object.freeze({tone:'blue',icon:'♙',value:'337',label:'إجمالي المشاركين',trend:'↑ 12%',trendDirection:'up'}),
      Object.freeze({tone:'green',icon:'✓',value:'268',label:'تم تسجيلهم',trend:'↑ 8%',trendDirection:'up'}),
      Object.freeze({tone:'orange',icon:'◷',value:'69',label:'قيد التأكيد',trend:'↓ 5%',trendDirection:'down'}),
      Object.freeze({tone:'red',icon:'×',value:'12',label:'معلق / مشكلة',trend:'↓ 2%',trendDirection:'down'}),
      Object.freeze({tone:'purple',icon:'▣',value:'156',label:'غرف محجوزة',trend:'↑ 85%',trendDirection:'up'}),
      Object.freeze({tone:'cyan',icon:'♜',value:'320',label:'وجبات مؤكدة',trend:'↑ 75%',trendDirection:'up'}),
      Object.freeze({tone:'gold',icon:'▤',value:'493,450',unit:'ج.م',label:'إجمالي المدفوعات',trend:'↑ 18%',trendDirection:'up'})
    ]),
    bookings:Object.freeze([
      Object.freeze({id:'RV-1026',name:'أحمد محمد',phone:'010 2456 8891',email:'ahmed@example.test',location:'القاهرة',type:'غرفة مزدوجة',date:'15 سبتمبر 2026',status:'confirmed',statusLabel:'مؤكد',paymentLabel:'مدفوع جزئيًا',attendance:'attended',attendanceLabel:'حضر',amount:'2,500 ج.م',notes:'يفضل غرفة قريبة من المصعد. تم تأكيد بيانات الوصول هاتفيًا.'}),
      Object.freeze({id:'RV-1025',name:'سارة علي',phone:'011 7832 1140',email:'',location:'',type:'غرفة فردية',date:'15 سبتمبر 2026',status:'pending',statusLabel:'قيد التأكيد',paymentLabel:'غير مكتمل',attendance:'pending',attendanceLabel:'لم يسجل',amount:'1,800 ج.م',notes:''}),
      Object.freeze({id:'RV-1024',name:'خالد نبيل',phone:'012 9941 0223',email:'',location:'',type:'بدون غرفة',date:'14 سبتمبر 2026',status:'paid',statusLabel:'مدفوع',paymentLabel:'مدفوع',attendance:'attended',attendanceLabel:'حضر',amount:'1,200 ج.م',notes:''}),
      Object.freeze({id:'RV-1023',name:'منى يوسف',phone:'010 6678 2031',email:'',location:'',type:'غرفة ثلاثية',date:'14 سبتمبر 2026',status:'cancelled',statusLabel:'ملغي',paymentLabel:'—',attendance:'absent',attendanceLabel:'غائب',amount:'2,700 ج.م',notes:''}),
      Object.freeze({id:'RV-1022',name:'إياد حياة',phone:'015 4002 1862',email:'',location:'',type:'بدون غرفة',date:'14 سبتمبر 2026',status:'confirmed',statusLabel:'مؤكد',paymentLabel:'مدفوع',attendance:'corrected',attendanceLabel:'تم التصحيح',amount:'1,200 ج.م',notes:''}),
      Object.freeze({id:'RV-1021',name:'مريم فؤاد',phone:'010 3320 6714',email:'',location:'',type:'غرفة مزدوجة',date:'13 سبتمبر 2026',status:'waiting',statusLabel:'قائمة انتظار',paymentLabel:'غير مكتمل',attendance:'pending',attendanceLabel:'لم يسجل',amount:'2,500 ج.م',notes:''})
    ])
  });

  function metricCards(items){
    return items.map(function(item){
      return '<article><span class="rvp-metric-icon rvp-tone-'+item.tone+'">'+item.icon+'</span><div><strong title="'+item.value+(item.unit?' '+item.unit:'')+'">'+item.value+(item.unit?' <em>'+item.unit+'</em>':'')+'</strong><span>'+item.label+'</span><small class="rvp-'+item.trendDirection+'">'+item.trend+'</small></div></article>';
    }).join('');
  }

  function bookingRows(items){
    return items.map(function(item,index){
      return '<tr data-booking-row="'+item.id+'">'+
        '<td><strong class="rvp-reference">#'+(1026-index)+'</strong></td>'+
        '<td><span class="rvp-person"><span class="rvp-avatar">'+item.name.charAt(0)+'</span><span><strong>'+item.name+'</strong><small>'+item.id+'</small></span></span></td>'+
        '<td><span class="rvp-cell-primary">'+item.type+'</span><small class="rvp-cell-secondary">'+item.attendanceLabel+'</small></td>'+
        '<td><span class="rvp-badge rvp-badge--'+item.status+'">'+item.statusLabel+'</span></td>'+
        '<td><span class="rvp-cell-primary">'+item.amount+'</span><small class="rvp-cell-secondary">'+item.paymentLabel+'</small></td><td>'+item.date+'</td>'+
        '<td><span class="rvp-row-actions"><button type="button" aria-label="تعديل">✎</button><button type="button" aria-label="رسالة">▣</button><button class="rvp-icon-button" type="button" data-open-details="'+item.id+'" aria-label="عرض تفاصيل '+item.name+'">•••</button></span></td></tr>';
    }).join('');
  }

  function mobileCards(items){
    return items.map(function(item){
      return '<article class="rvp-booking-card" data-booking-card="'+item.id+'"><header><span class="rvp-person"><span class="rvp-avatar">'+item.name.charAt(0)+'</span><span><strong>'+item.name+'</strong><small>'+item.id+'</small></span></span><span class="rvp-badge rvp-badge--'+item.status+'">'+item.statusLabel+'</span></header><dl><div><dt>نوع الحجز</dt><dd>'+item.type+'</dd></div><div><dt>التاريخ</dt><dd>'+item.date+'</dd></div><div><dt>الحضور</dt><dd>'+item.attendanceLabel+'</dd></div><div><dt>القيمة</dt><dd>'+item.amount+'</dd></div></dl><button type="button" class="rvp-button rvp-button--soft" data-open-details="'+item.id+'">عرض التفاصيل</button></article>';
    }).join('');
  }

  function shell(viewModel){
    var context=viewModel.context;
    var bookings=viewModel.bookings;
    return '<section class="rvp-workspace" data-reservations-prototype-root data-prototype-state="populated">'+
      '<div class="rvp-dashboard">'+
        '<section class="rvp-hero"><div class="rvp-hero__welcome"><span>مرحبًا بك</span><h1>منصة الإدارة المتكاملة</h1><p>كل ما تحتاجه لتنظيم مؤتمرات ناجحة في مكان واحد</p></div><div class="rvp-event"><div class="rvp-event__art" role="img" aria-label="صورة مؤتمر الشباب"></div><div class="rvp-event__copy"><span class="rvp-badge rvp-badge--active">'+context.status+'</span><h2 title="'+context.title+'">'+context.title+'</h2><p>▣ '+context.period+'</p><p>⌖ '+context.location+'</p><button type="button" class="rvp-button rvp-button--primary">فتح المؤتمر ←</button></div></div><div class="rvp-hero__statement"><p>« تنظيم أفضل · خدمة أسرع · تجربة أمتع »</p><span class="rvp-trend" aria-hidden="true">↗</span></div></section>'+
        '<section class="rvp-metrics" aria-label="ملخص الحجوزات">'+metricCards(viewModel.metrics)+'</section>'+
        '<nav class="rvp-actions" aria-label="إجراءات سريعة"><button type="button" data-open-form><span class="rvp-tone-blue">♙</span>تسجيل مشارك</button><button type="button"><span class="rvp-tone-green">▰</span>حجز غرفة</button><button type="button"><span class="rvp-tone-purple">▦</span>تسجيل حضور</button><button type="button"><span class="rvp-tone-orange">▤</span>استلام سداد</button><button type="button"><span class="rvp-tone-blue">⌕</span>البحث السريع</button><button type="button"><span class="rvp-tone-red">▧</span>إصدار شهادة</button><button type="button"><span class="rvp-tone-blue">▣</span>إضافة ملاحظة</button><button type="button"><span>•••</span>المزيد</button></nav>'+
        '<section class="rvp-insights">'+
          '<article class="rvp-panel rvp-alerts"><header><h3>إجراءات عاجلة</h3><span>●</span></header><ul><li><i class="rvp-dot rvp-red"></i><span>حجوزات تحتاج تأكيد</span><strong>4</strong></li><li><i class="rvp-dot rvp-orange"></i><span>مدفوعات غير مكتملة</span><strong>2</strong></li><li><i class="rvp-dot rvp-orange"></i><span>طلبات خاصة جديدة</span><strong>3</strong></li><li><i class="rvp-dot rvp-red"></i><span>مشاكل في الحضور</span><strong>1</strong></li><li><i class="rvp-dot rvp-purple"></i><span>رسائل غير مقروءة</span><strong>5</strong></li></ul><button type="button" class="rvp-link">عرض كل التنبيهات ←</button></article>'+
          '<article class="rvp-panel rvp-ring-panel"><header><h3>معدل الإشغال</h3><span>▦</span></header><div class="rvp-ring-layout"><div class="rvp-ring" style="--progress:68%;--ring:#0a6fff"><strong>68%</strong><small>من الإجمالي</small></div><div class="rvp-legend"><span><i class="rvp-blue"></i>محجوزة <b>156</b></span><span><i class="rvp-cyan"></i>متاحة <b>74</b></span><span><i class="rvp-red"></i>صيانة <b>8</b></span></div></div><button type="button" class="rvp-panel-action">إدارة الغرف ←</button></article>'+
          '<article class="rvp-panel rvp-ring-panel"><header><h3>حالة التسجيل</h3><span>♙</span></header><div class="rvp-ring-layout"><div class="rvp-ring" style="--progress:88%;--ring:#00c853"><strong>88%</strong><small>مكتمل</small></div><div class="rvp-legend"><span><i class="rvp-green"></i>مؤكد <b>268</b></span><span><i class="rvp-orange"></i>قيد التأكيد <b>69</b></span><span><i class="rvp-red"></i>مرفوض <b>12</b></span></div></div><button type="button" class="rvp-panel-action">إدارة التسجيل ←</button></article>'+
          '<article class="rvp-panel rvp-ring-panel"><header><h3>حالة السداد</h3><span>▣</span></header><div class="rvp-ring-layout"><div class="rvp-ring" style="--progress:76%;--ring:#00bcd4"><strong>76%</strong><small>تم التحصيل</small></div><div class="rvp-legend"><span><i class="rvp-cyan"></i>مدفوع <b>493,450</b></span><span><i class="rvp-blue"></i>متبقي <b>155,200</b></span><span><i class="rvp-orange"></i>متأخر <b>28,600</b></span></div></div><button type="button" class="rvp-panel-action">متابعة المدفوعات ←</button></article>'+
          '<article class="rvp-panel rvp-chart"><header><h3>الحضور خلال الأيام</h3><button type="button">هذا الأسبوع⌄</button></header><div class="rvp-bars"><span style="--height:38%"><b>120</b><i></i><small>السبت</small></span><span style="--height:72%"><b>280</b><i></i><small>الأربعاء</small></span><span style="--height:88%"><b>310</b><i></i><small>الخميس</small></span><span style="--height:68%"><b>275</b><i></i><small>الجمعة</small></span><span style="--height:54%"><b>200</b><i></i><small>الثلاثاء</small></span></div><button type="button" class="rvp-panel-action">عرض التفاصيل ←</button></article>'+
        '</section>'+
        '<section class="rvp-operations">'+
          '<aside class="rvp-side-stack rvp-side-stack--right"><article class="rvp-panel rvp-quick-search"><header><h3>بحث سريع</h3><span>♙</span></header>'+filterBar()+'</article><article class="rvp-panel rvp-tools"><header><h3>أدوات سريعة</h3></header><div><button type="button"><i>♙</i>طباعة شهادة</button><button type="button"><i>↧</i>تصدير تقرير</button><button type="button"><i>↥</i>استيراد بيانات</button><button type="button"><i>▣</i>إرسال رسالة</button><button type="button"><i>↪</i>تحويل حجز</button><button type="button"><i>×</i>إلغاء حجز</button></div></article></aside>'+
          '<article class="rvp-panel rvp-list-panel"><div class="rvp-table-tabs"><button type="button" class="is-active">أحدث الحجوزات</button><button type="button">أحدث التسجيلات</button><button type="button">المدفوعات الأخيرة</button><button type="button">الملاحظات</button><button type="button">المهام</button><span class="rvp-view-switch" aria-label="حالة العرض"><button type="button" data-view-state="populated" class="is-active">●</button><button type="button" data-view-state="loading">◌</button><button type="button" data-view-state="empty">□</button><button type="button" data-view-state="error">!</button></span></div><div class="rvp-table-wrap"><table><thead><tr><th>#</th><th>الاسم</th><th>نوع الحجز</th><th>الحالة</th><th>المبلغ</th><th>تاريخ الحجز</th><th>إجراءات</th></tr></thead><tbody data-booking-rows>'+bookingRows(bookings)+'</tbody></table></div><div class="rvp-mobile-list" data-mobile-bookings>'+mobileCards(bookings)+'</div>'+stateSurfaces()+'<footer><button type="button" class="rvp-link-button">عرض جميع الحجوزات ←</button><span>'+bookings.length+' من 337</span></footer></article>'+
          '<aside class="rvp-panel rvp-schedule"><header><h3>جدول اليوم</h3><span>الأحد 15 سبتمبر 2026</span></header><ol><li><time>08:00</time><span>استقبال المشاركين</span></li><li><time>10:00</time><span>الجلسة الافتتاحية</span></li><li><time>12:30</time><span>استراحة وغداء</span></li><li><time>14:00</time><span>ورش العمل</span></li><li><time>18:00</time><span>المساء الترفيهي</span></li></ol><button type="button" class="rvp-panel-action">عرض الجدول الكامل ←</button></aside>'+
        '</section>'+
      '</div>'+detailsDrawer()+formDialog()+'</section>';
  }

  function filterBar(){
    return '<div class="rvp-filters"><label class="rvp-search"><span>⌕</span><input type="search" data-search placeholder="الاسم أو رقم الحجز أو الهاتف..." aria-label="البحث في الحجوزات"></label><div class="rvp-filter-chips"><button type="button">مشارك</button><button type="button">حجز</button><button type="button">دفعة</button><button type="button">غرفة</button></div><select data-status-filter aria-label="تصفية حسب الحالة"><option value="">كل الحالات</option><option value="confirmed">مؤكد</option><option value="pending">قيد التأكيد</option><option value="waiting">قائمة انتظار</option><option value="cancelled">ملغي</option></select><select data-type-filter aria-label="تصفية حسب نوع الحجز"><option value="">كل أنواع الحجز</option><option>غرفة مزدوجة</option><option>غرفة فردية</option><option>غرفة ثلاثية</option><option>بدون غرفة</option></select><button class="rvp-button rvp-button--primary" type="button">⌕ بحث</button><button class="rvp-reset" type="button" data-reset-filters>مسح الفلاتر</button><span class="rvp-active-filter" data-filter-summary hidden></span></div>';
  }

  function stateSurfaces(){
    return '<div class="rvp-state rvp-state--loading" data-state-surface="loading"><span class="rvp-spinner"></span><strong>جارٍ تحميل الحجوزات...</strong><small>يتم تجهيز أحدث بيانات التشغيل</small></div><div class="rvp-state rvp-state--empty" data-state-surface="empty"><span>▤</span><strong>لا توجد حجوزات بعد</strong><small>ابدأ بإضافة أول حجز لهذا المؤتمر.</small><button type="button" class="rvp-button rvp-button--primary" data-open-form>إضافة حجز</button></div><div class="rvp-state rvp-state--no-results" data-state-surface="no-results"><span>⌕</span><strong>لا توجد نتائج مطابقة</strong><small>غيّر عبارة البحث أو امسح الفلاتر النشطة.</small><button type="button" class="rvp-button rvp-button--soft" data-reset-filters>مسح الفلاتر</button></div><div class="rvp-state rvp-state--error" data-state-surface="error" role="alert"><span>!</span><strong>تعذر تحميل الحجوزات</strong><small>هذه حالة عرض تجريبية ولا يوجد اتصال بالخادم.</small><button type="button" class="rvp-button rvp-button--soft" data-view-state="populated">إعادة المحاولة</button></div>';
  }

  function detailsDrawer(){
    return '<div class="rvp-overlay" data-details-overlay hidden><aside class="rvp-drawer" role="dialog" aria-modal="true" aria-labelledby="rvp-details-title"><header><div><span class="rvp-context__eyebrow">تفاصيل الحجز</span><h2 id="rvp-details-title"></h2></div><button type="button" class="rvp-close" data-close-details aria-label="إغلاق">×</button></header><div class="rvp-drawer__body"><section class="rvp-profile"><span class="rvp-avatar rvp-avatar--large" data-detail-avatar></span><div><h3 data-detail-name></h3><p data-detail-phone></p></div><span class="rvp-badge" data-detail-status></span></section><section class="rvp-detail-grid"><div><span>نوع الحجز</span><strong data-detail-type></strong></div><div><span>التاريخ</span><strong data-detail-date></strong></div><div><span>القيمة</span><strong data-detail-amount></strong></div><div><span>حالة السداد</span><strong data-detail-payment></strong></div></section><section class="rvp-detail-section"><h3>بيانات التواصل</h3><dl><div><dt>رقم الهاتف</dt><dd data-detail-contact></dd></div><div><dt>البريد الإلكتروني</dt><dd data-detail-email></dd></div><div><dt>المحافظة</dt><dd data-detail-location></dd></div></dl></section><section class="rvp-detail-section"><div class="rvp-section-title"><h3>الحضور</h3><span class="rvp-badge rvp-badge--paid" data-detail-attendance></span></div><div class="rvp-attendance-box"><label><input type="radio" name="mock-attendance" checked> حضر</label><label><input type="radio" name="mock-attendance"> غائب</label><label>تاريخ الحضور<input type="date" value="2026-09-15"></label><label>ملاحظات<textarea rows="2">تم تسجيل الحضور عند البوابة الرئيسية.</textarea></label><button type="button" class="rvp-button rvp-button--soft" data-mock-correction>تسجيل تصحيح حضور</button><small data-correction-note hidden>تم عرض حالة التصحيح محليًا فقط.</small></div></section><section class="rvp-detail-section" data-detail-notes-section><h3>ملاحظات الحجز</h3><p data-detail-notes></p></section></div><footer><button type="button" class="rvp-button rvp-button--ghost" data-close-details>إغلاق</button><button type="button" class="rvp-button rvp-button--primary" data-open-form>تعديل الحجز</button></footer></aside></div>';
  }

  function formDialog(){
    return '<div class="rvp-overlay" data-form-overlay hidden><section class="rvp-modal" role="dialog" aria-modal="true" aria-labelledby="rvp-form-title" data-form-mode="default"><header><div><span class="rvp-context__eyebrow">تدفق تجريبي</span><h2 id="rvp-form-title">حجز جديد</h2></div><button type="button" class="rvp-close" data-close-form aria-label="إغلاق">×</button></header><div class="rvp-form-body"><div class="rvp-stepper"><span class="is-active">1 بيانات المشارك</span><span>2 تفاصيل الحجز</span><span>3 المراجعة</span></div><section class="rvp-form-section"><h3>بيانات المشارك</h3><div class="rvp-form-grid"><label>الاسم بالكامل <b>*</b><input value="مينا سامح" data-required-field></label><label>رقم الهاتف <b>*</b><input value="010 1234 5678"></label><label>البريد الإلكتروني<input type="email" placeholder="name@example.com"></label><label>المحافظة<select><option>القاهرة</option><option>الجيزة</option></select></label></div></section><section class="rvp-form-section"><h3>تفاصيل الحجز</h3><div class="rvp-form-grid"><label>نوع الحجز <b>*</b><select><option>غرفة مزدوجة</option><option>غرفة فردية</option><option>بدون غرفة</option></select></label><label>تاريخ الوصول<input type="date" value="2026-09-15"></label><label>تاريخ المغادرة<input type="date" value="2026-09-20"></label><label class="rvp-field--wide">ملاحظات<textarea rows="3" placeholder="أضف ملاحظات تشغيلية..."></textarea></label></div></section><div class="rvp-form-feedback rvp-form-feedback--validation" role="alert">يرجى استكمال الحقول المطلوبة قبل الحفظ.</div><div class="rvp-form-feedback rvp-form-feedback--saving" role="status"><span class="rvp-spinner"></span> جارٍ حفظ النموذج التجريبي...</div><div class="rvp-form-feedback rvp-form-feedback--success" role="status">✓ تم حفظ النموذج التجريبي بنجاح.</div><div class="rvp-form-feedback rvp-form-feedback--error" role="alert">تعذر الحفظ في حالة العرض التجريبية.</div><div class="rvp-form-state-controls"><span>معاينة الحالة:</span><button type="button" data-form-state="validation">تحقق</button><button type="button" data-form-state="saving">حفظ</button><button type="button" data-form-state="success">نجاح</button><button type="button" data-form-state="error">خطأ</button><button type="button" data-form-state="default">إعادة</button></div></div><footer><button type="button" class="rvp-button rvp-button--ghost" data-close-form>إلغاء</button><button type="button" class="rvp-button rvp-button--primary" data-form-state="saving">حفظ الحجز</button></footer></section></div>';
  }

  function on(target,type,handler){target.addEventListener(type,handler);listeners.push(function(){target.removeEventListener(type,handler);});}
  function setHidden(element,hidden){if(element)element.hidden=hidden;}
  function openDetails(id){
    var booking=mockViewModel.bookings.find(function(item){return item.id===id;})||mockViewModel.bookings[0];
    root.querySelector('#rvp-details-title').textContent=booking.id;
    root.querySelector('[data-detail-name]').textContent=booking.name;
    root.querySelector('[data-detail-phone]').textContent=booking.phone;
    root.querySelector('[data-detail-contact]').textContent=booking.phone;
    root.querySelector('[data-detail-type]').textContent=booking.type;
    root.querySelector('[data-detail-date]').textContent=booking.date;
    root.querySelector('[data-detail-amount]').textContent=booking.amount;
    root.querySelector('[data-detail-avatar]').textContent=booking.name.charAt(0);
    root.querySelector('[data-detail-status]').textContent=booking.statusLabel;
    root.querySelector('[data-detail-status]').className='rvp-badge rvp-badge--'+booking.status;
    root.querySelector('[data-detail-payment]').textContent=booking.paymentLabel||'—';
    root.querySelector('[data-detail-attendance]').textContent=booking.attendanceLabel||'—';
    root.querySelector('[data-detail-email]').textContent=booking.email||'—';
    root.querySelector('[data-detail-location]').textContent=booking.location||'—';
    root.querySelector('[data-detail-notes]').textContent=booking.notes||'';
    setHidden(root.querySelector('[data-detail-notes-section]'),!booking.notes);
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
    var matches=mockViewModel.bookings.filter(function(item){return (!query||(item.name+' '+item.phone+' '+item.id).toLowerCase().includes(query))&&(!status||item.status===status)&&(!type||item.type===type);});
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
    if(!trigger||(!root.contains(trigger)&&!trigger.closest('[data-rvp-shell-header]')))return;
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
  function prototypeHeader(){
    return '<div class="rvp-shell-header" data-rvp-shell-header><div class="rvp-header-account"><span class="rvp-header-avatar">D</span><span><strong>dev-owner-test@example.com</strong><small>صاحب الحساب</small></span></div><div class="rvp-header-utilities"><button type="button" aria-label="الرسائل">✉</button><button type="button" aria-label="الإشعارات" class="rvp-notification">♧<b>3</b></button><button type="button" class="rvp-quick-add" data-open-form>＋ <span>إضافة سريع</span></button><label><input type="search" placeholder="ابحث بالاسم أو رقم الحجز أو الهاتف أو البريد ..."><span>⌕</span></label></div><div class="rvp-header-brand"><img src="assets/make-a-difference-logo.png" alt=""><span><strong>منظومة الإدارة المتكاملة</strong><small lang="en" dir="ltr">Integrated Management Platform</small></span></div></div>';
  }
  function prototypeSidebar(){
    var items=[['⌂','الرئيسية'],['▤','المؤتمرات'],['□','الحجوزات'],['◇','المخازن'],['♜','المطاعم'],['▰','النقل'],['▥','المالية'],['▧','التقارير'],['♙','المستخدمين'],['⚙','الإعدادات']];
    return '<div class="rvp-shell-sidebar" data-rvp-shell-sidebar><div class="rvp-sidebar-brand"><img src="assets/make-a-difference-logo.png" alt=""><span><strong>منظومة الإدارة المتكاملة</strong><small lang="en" dir="ltr">Integrated Management Platform</small></span></div><nav>'+items.map(function(item,index){return '<button type="button"'+(index===0?' class="is-active"':'')+(index>2?' disabled aria-disabled="true"':'')+'><i>'+item[0]+'</i><span>'+item[1]+'</span></button>';}).join('')+'</nav><article class="rvp-promo"><span>معًا</span><strong>نصنع فرقًا</strong><i aria-hidden="true">▲</i></article><footer><span><i></i>متصل</span><b>v 3.5.0</b></footer></div>';
  }
  function mountShellChrome(){
    var header=global.document.querySelector('[data-canonical-platform-header]');
    var sidebar=global.document.querySelector('[data-canonical-platform-sidebar]');
    if(header&&!header.querySelector('[data-rvp-shell-header]'))header.insertAdjacentHTML('beforeend',prototypeHeader());
    if(sidebar&&!sidebar.querySelector('[data-rvp-shell-sidebar]'))sidebar.insertAdjacentHTML('beforeend',prototypeSidebar());
  }
  function unmountShellChrome(){
    global.document.querySelectorAll('[data-rvp-shell-header],[data-rvp-shell-sidebar]').forEach(function(element){element.remove();});
  }
  function mount(context){
    if(!context||!(context.container instanceof global.HTMLElement))throw new Error('PLATFORM_MODULE_CONTAINER_REQUIRED');
    if(root&&root!==context.container)unmount();
    root=context.container;
    root.innerHTML=shell(mockViewModel);
    mountShellChrome();
    on(root,'click',handleClick);
    var shellHeader=global.document.querySelector('[data-rvp-shell-header]');
    if(shellHeader)on(shellHeader,'click',handleClick);
    on(root,'input',handleInput);
    on(root,'change',handleChange);
    return true;
  }
  function unmount(){listeners.splice(0).forEach(function(remove){remove();});unmountShellChrome();if(root)root.innerHTML='';root=null;return true;}

  var moduleDefinition=Object.freeze({id:MODULE_ID,mount:mount,unmount:unmount,reconcileRoute:function(context){return root?true:mount(context);}});
  if(!global.PlatformIntegration||typeof global.PlatformIntegration.registerModule!=='function')throw new Error('PLATFORM_MODULE_REGISTRY_REQUIRED');
  global.ReservationsVisualPrototype=Object.freeze({mockViewModel:mockViewModel,mockBookings:mockViewModel.bookings,module:moduleDefinition});
  global.PlatformIntegration.registerModule(moduleDefinition);
})(window);
