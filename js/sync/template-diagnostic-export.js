(function(global){
  'use strict';

  function text(value){return value==null?null:String(value);}
  function number(value){
    return value===null||value===undefined||value===''
      ?null:Number.isInteger(Number(value))?Number(value):null;
  }
  function templateRow(template){
    return {
      id:text(template&&template.id),
      name:text(template&&template.name),
      revision:number(template&&template.revision),
      createdAt:text(template&&template.createdAt),
      updatedAt:text(template&&template.updatedAt)
    };
  }
  function context(options){
    var auth=options.auth||global.SupabaseAuth;
    var authState=auth&&typeof auth.getState==='function'
      ?auth.getState():null;
    var identity=options.deviceIdentity||global.SupabaseDeviceIdentity;
    var device=identity&&typeof identity.getCurrent==='function'
      ?identity.getCurrent():null;
    return {
      currentUserId:text(authState&&authState.user&&authState.user.id),
      currentDeviceId:text(device&&device.id),
      timestamp:new Date().toISOString()
    };
  }
  function createBundle(options){
    options=options||{};
    var data=options.appData||global.appData||{};
    return Promise.resolve({
      context:context(options),
      houseTemplates:(Array.isArray(data.houseTemplates)
        ?data.houseTemplates:[]).map(templateRow)
    });
  }
  function fileName(bundle){
    return 'template-diagnostic_'+String(
      bundle&&bundle.context&&bundle.context.timestamp||''
    )
      .replace(/[:.]/g,'-')+'.json';
  }
  function download(bundle,options){
    options=options||{};
    var documentApi=options.document||global.document;
    var urlApi=options.URL||global.URL;
    if(!documentApi||!urlApi||typeof global.Blob!=='function'){
      throw new Error('DOWNLOAD_API_UNAVAILABLE');
    }
    var blob=new global.Blob([JSON.stringify(bundle,null,2)],{
      type:'application/json'
    });
    var url=urlApi.createObjectURL(blob);
    var anchor=documentApi.createElement('a');
    anchor.href=url;
    anchor.download=fileName(bundle);
    anchor.rel='noopener';
    anchor.click();
    urlApi.revokeObjectURL(url);
    return anchor.download;
  }
  function exportBundle(options){
    return createBundle(options).then(function(bundle){
      return {bundle:bundle,fileName:download(bundle,options)};
    });
  }

  global.TemplateDiagnosticExport=Object.freeze({
    createBundle:createBundle,
    exportBundle:exportBundle,
    download:download,
    fileName:fileName
  });
})(window);
