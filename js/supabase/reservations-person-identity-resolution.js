(function(global){
  'use strict';
  var session=global.PlatformDeviceSession;
  if(!session||typeof session.invokeModuleProtected!=='function')throw new Error('PLATFORM_DEVICE_SESSION_REQUIRED');
  var original=session.invokeModuleProtected.bind(session);
  var queue=Promise.resolve();
  var profileFields=[
    ['fullName','الاسم'],['phone','الهاتف'],['gender','النوع'],
    ['dateOfBirth','تاريخ الميلاد'],['church','الكنيسة'],
    ['governorate','المحافظة'],['cityOrVillage','المدينة / القرية'],
    ['serviceSector','قطاع الخدمة'],['serviceSectorOther','تفاصيل القطاع']
  ];
  function value(item,key){var result=item&&item[key];return result===null||result===undefined||result===''?'—':String(result);}
  function draft(args){return{
    fullName:args.p_full_name,phone:args.p_phone,gender:args.p_gender,
    dateOfBirth:args.p_date_of_birth,church:args.p_church,
    governorate:args.p_governorate,cityOrVillage:args.p_city_or_village,
    serviceSector:args.p_service_sector,serviceSectorOther:args.p_service_sector_other
  };}
  function changed(candidate,args){var local=draft(args);return profileFields.some(function(field){
    return value(candidate,field[0]).trim()!==value(local,field[0]).trim();
  });}
  function button(label,variant,action){
    var node=document.createElement('button');node.type='button';node.textContent=label;
    node.className=variant==='primary'?'inline-flex h-10 items-center justify-center rounded-md bg-primary px-4 font-bold text-primary-foreground':'inline-flex h-10 items-center justify-center rounded-md border border-border bg-background px-4 font-bold';
    node.addEventListener('click',action);return node;
  }
  function dialog(title,description,render){return new Promise(function(resolve){
    var overlay=document.createElement('div');overlay.className='fixed inset-0 z-[100] grid place-items-center bg-black/50 p-4';
    var panel=document.createElement('section');panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');panel.className='max-h-[88dvh] w-full max-w-3xl overflow-y-auto rounded-lg border border-border bg-card p-5 text-card-foreground shadow-xl';
    var heading=document.createElement('h2');heading.className='text-lg font-extrabold';heading.textContent=title;
    var help=document.createElement('p');help.className='mt-1 text-sm text-muted-foreground';help.textContent=description;
    var body=document.createElement('div');body.className='mt-5 space-y-3';
    panel.appendChild(heading);panel.appendChild(help);panel.appendChild(body);overlay.appendChild(panel);document.body.appendChild(overlay);
    function finish(result){overlay.remove();resolve(result);}render(body,finish);
  });}
  function chooseIdentity(challenge){return dialog('يوجد شخص محتمل مطابق في الدليل المركزي','راجع البيانات قبل إنشاء هوية جديدة. تشابه الاسم أو الهاتف وحده لا يعني أن الشخص نفسه.',function(body,finish){
    challenge.candidates.forEach(function(candidate){
      var card=document.createElement('div');card.className='rounded-md border border-border p-3';
      var name=document.createElement('h3');name.className='font-extrabold';name.textContent=value(candidate,'fullName');card.appendChild(name);
      var grid=document.createElement('dl');grid.className='mt-2 grid gap-2 text-sm sm:grid-cols-2 lg:grid-cols-3';
      profileFields.slice(1).forEach(function(field){var row=document.createElement('div');var term=document.createElement('dt');term.className='text-muted-foreground';term.textContent=field[1];var detail=document.createElement('dd');detail.className='font-bold';detail.textContent=value(candidate,field[0]);row.appendChild(term);row.appendChild(detail);grid.appendChild(row);});
      card.appendChild(grid);card.appendChild(button('اختيار الشخص الموجود','primary',function(){finish({decision:'existing',candidate:candidate});}));body.appendChild(card);
    });
    var actions=document.createElement('div');actions.className='flex flex-col gap-2 border-t border-border pt-3 sm:flex-row sm:justify-end';
    actions.appendChild(button('الرجوع للتعديل','secondary',function(){finish({decision:'cancel'});}));
    actions.appendChild(button('هذا شخص مختلف','secondary',function(){finish({decision:'different'});}));body.appendChild(actions);
  });}
  function chooseScope(){return dialog('تحديد نطاق حفظ بيانات الشخص','بيانات النموذج مختلفة عن بيانات الدليل المركزي. اختر نطاق الحفظ دون اختيار افتراضي.',function(body,finish){
    body.appendChild(button('حفظ التعديلات في الحجز الحالي فقط','secondary',function(){finish('save-local');}));
    body.appendChild(button('تحديث بيانات الشخص في الدليل المركزي','primary',function(){finish('update-canonical');}));
    body.appendChild(button('إلغاء والعودة للنموذج','secondary',function(){finish('cancel');}));
  });}
  function resolveChallenge(args,challenge){
    queue=queue.catch(function(){}).then(function(){return chooseIdentity(challenge);});
    return queue.then(function(choice){
      if(choice.decision==='cancel')throw {code:'RESERVATIONS_PERSON_IDENTITY_RESOLUTION_CANCELLED',message:'تم الرجوع إلى نموذج الحجز دون حفظ.'};
      var retry=Object.assign({},args,{p_identity_resolution_token:challenge.identityResolutionToken,p_identity_resolution_decision:choice.decision});
      if(choice.decision==='different'){delete retry.p_person_id;delete retry.p_person_update_revision;return original('reservations','create_booking',retry);}
      retry.p_person_id=choice.candidate.personId;
      if(!changed(choice.candidate,args))return original('reservations','create_booking',retry);
      return chooseScope().then(function(scope){
        if(scope==='cancel')throw {code:'RESERVATIONS_PERSON_IDENTITY_RESOLUTION_CANCELLED',message:'تم الرجوع إلى نموذج الحجز دون حفظ.'};
        if(scope==='update-canonical')retry.p_person_update_revision=choice.candidate.revision;
        return original('reservations','create_booking',retry);
      });
    });
  }
  function invokeModuleProtected(module,operation,args){
    return original(module,operation,args).then(function(result){
      if(module==='reservations'&&operation==='create_booking'&&result&&result.identityResolutionRequired===true&&result.identityResolutionToken&&Array.isArray(result.candidates))return resolveChallenge(args||{},result);
      return result;
    });
  }
  global.PlatformDeviceSession=Object.freeze({
    establish:session.establish,ensureValid:session.ensureValid,validFor:session.validFor,
    invokeProtected:function(operation,args){return invokeModuleProtected('conference',operation,args);},
    invokeModuleProtected:invokeModuleProtected,verify:session.verify,getSession:session.getSession,clear:session.clear
  });
})(window);
