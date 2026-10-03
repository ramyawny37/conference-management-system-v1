(function(global){
  'use strict';
  // P6C1: conference-role membership mutation attempts are retired.
  // Keep a fail-closed compatibility surface until all historical callers/tests are removed.
  function retired(){return Promise.resolve({ok:false,status:'retired',data:null,error:{code:'LEGACY_CONFERENCE_MEMBERSHIP_RETIRED',message:'Legacy conference membership authority is retired.'}});}
  global.ConferenceMembershipAttemptStore=Object.freeze({
    get:retired,save:retired,remove:retired,clear:retired,
    resetForTests:function(){return {ok:true,status:'reset'};}
  });
})(window);
