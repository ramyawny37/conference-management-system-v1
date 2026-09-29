(function(global){
  'use strict';
  var canonicalConference=[
    ['create_canonical_conference','public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date)'],
    ['mutate_conference_core','public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text)'],
    ['get_conference_core','public.get_conference_core(uuid,uuid)'],
    ['list_conference_participations','public.list_conference_participations(uuid,uuid)'],
    ['create_conference_participation','public.create_conference_participation(uuid,uuid,uuid,uuid)'],
    ['create_conference_participation_with_person','public.create_conference_participation_with_person(uuid,uuid,uuid,text,text,text,date,text)'],
    ['set_conference_participation_status','public.set_conference_participation_status(uuid,uuid,uuid,bigint,text)'],
    ['delete_conference_participation','public.delete_conference_participation(uuid,uuid,uuid,bigint)'],
    ['get_conference_accommodation','public.get_conference_accommodation(uuid,uuid)'],
    ['create_accommodation_house','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['update_accommodation_house','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['delete_accommodation_house','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['create_accommodation_floor','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['update_accommodation_floor','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['delete_accommodation_floor','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['create_accommodation_room','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['update_accommodation_room','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['delete_accommodation_room','public.mutate_conference_accommodation_structure(uuid,text,jsonb)'],
    ['assign_conference_accommodation','public.assign_conference_accommodation(uuid,uuid,uuid,uuid,integer,integer,text,text)'],
    ['move_conference_accommodation','public.move_conference_accommodation(uuid,uuid,uuid,bigint,uuid,integer,integer,text,text)'],
    ['remove_conference_accommodation','public.remove_conference_accommodation(uuid,uuid,uuid,bigint)']
  ].map(function(entry){return Object.freeze({module:'conference',operation:entry[0],signature:entry[1],dispatchable:true});});
  var conference=canonicalConference.concat(global.ConferenceDeviceOperationContract.EDGE_ONLY_PROTECTED.map(function(entry){return Object.freeze({module:'conference',operation:entry.operation,signature:entry.signature,dispatchable:true});}));
  var warehouse=global.WarehouseDeviceOperationContract.DISPATCHABLE;
  global.PlatformDeviceOperationContract=Object.freeze({CONFERENCE:Object.freeze(conference),WAREHOUSE:warehouse,DISPATCHABLE:Object.freeze(conference.concat(warehouse)),isAllowed:function(module,operation){return module==='conference'?conference.some(function(entry){return entry.operation===operation;}):module==='warehouse'&&!!(global.WarehouseDeviceOperationContract.get(operation)||{}).dispatchable;}});
})(window);
