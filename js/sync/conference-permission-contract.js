(function(global){
  'use strict';
  // P6C1: legacy conference-role permission bundles are retired.
  // Runtime authorization is owned by the canonical platform permission system.
  function deny(){return false;}
  global.ConferencePermissionContract=Object.freeze({
    enforcementEnabled:false,
    retired:true,
    sections:Object.freeze([]),
    actions:Object.freeze([]),
    conferenceActions:Object.freeze([]),
    roles:Object.freeze([]),
    roleBundles:Object.freeze({}),
    mutationCatalog:Object.freeze([]),
    conferenceMutationCatalog:Object.freeze([]),
    futureActionCandidates:Object.freeze([]),
    semanticBoundaries:Object.freeze(['platform_permission']),
    nonAuthorizationSignals:Object.freeze(['conference_role','local_presence','frontend_visibility']),
    lockSemantics:'concurrency_precondition_only',
    hasSectionPermission:deny,
    hasConferencePermission:deny
  });
})(window);
