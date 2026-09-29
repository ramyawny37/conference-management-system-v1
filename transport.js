function isCanonicalTransportConference(conference){
  return !!(conference&&window.CanonicalConferenceTransport&&window.CanonicalConferenceTransport.isLinked(conference.id));
}

function getConferenceTransportVehicles(conference){
  if(!conference)return [];
  return isCanonicalTransportConference(conference)?window.CanonicalConferenceTransport.getVehicles(conference.id):(conference.transports||[]);
}

function assignedNames(){
  var current = getCurrentConference();
  if (!current) return {};
  var n={};
  getConferenceTransportVehicles(current).forEach(function(t){
    (t.seats || []).forEach(function(s){
      if(s.name&&s.type!=='child_shared'&&s.type!=='infant')n[s.name]=true;
    });
  });
  return n;
}

function activeGuests(day){ // day=undefined means current/total
  var current = getCurrentConference();
  if (!current) return { adults: [], children: [] };
  if(isCanonicalTransportConference(current)){
    var canonical=window.CanonicalConferenceTransport.getActiveParticipations(current.id),adults=[],children=[];
    canonical.forEach(function(participation){
      var item={name:participation.person&&participation.person.fullName||'',room:'',personId:participation.personId||'',participationId:participation.participationId||'',guardian:participation.guardianFullName||'',guardianPersonId:participation.guardianPersonId||'',guardianParticipationId:participation.guardianParticipationId||null,guardianParticipationStatus:participation.guardianParticipationStatus||null};
      if(participation.guardianParticipationId)children.push(item);else adults.push(item);
    });
    return {adults:adults,children:children};
  }
  var adults=[],children=[];
  getAllRooms().forEach(function(r) {
    if (!isRoomActiveOnDay(r, day)) return;
    getConferenceRoomPeopleOnDay(r,day,current).forEach(function(person){
      var item={name:person.name||gn(person),room:r.number,rid:r.id,personId:person.personId||'',participationId:person.participationId||'',guardian:person.guardianFullName||person.guardian||'',guardianPersonId:person.guardianPersonId||'',guardianParticipationId:person.guardianParticipationId||null,guardianParticipationStatus:person.guardianParticipationStatus||null};
      if(person.isChild)children.push(item);else adults.push(item);
    });
  });
  return {adults:adults,children:children};
}

function unassigned(curName){
  var current=getCurrentConference();
  if(isCanonicalTransportConference(current)){
    var transportState=window.CanonicalConferenceTransport.getState(current.id),assigned={};
    ((transportState&&transportState.assignments)||[]).forEach(function(item){assigned[item.participationId]=true;});
    var active=activeGuests(),all=active.adults.concat(active.children);
    return all.filter(function(item){return !assigned[item.participationId]||item.name===curName;});
  }
  var assigned=assignedNames();
  var ag = activeGuests();
  var allActive = ag.adults.concat(ag.children);
  var unassignedGuests = [];
  for (var i = 0; i < allActive.length; i++) {
    if (!assigned[allActive[i].name] || allActive[i].name === curName) {
      unassignedGuests.push(allActive[i]);
    }
  }
  return unassignedGuests;
}

function allGuestsForPick(){
  var l=[];
  var current=getCurrentConference();
  if(isCanonicalTransportConference(current)){
    return window.CanonicalConferenceTransport.getActiveParticipations(current.id).map(function(participation){return {name:participation.person&&participation.person.fullName||'',room:'',guardian:participation.guardianFullName||null,personId:participation.personId||'',participationId:participation.participationId||'',guardianParticipationId:participation.guardianParticipationId||null,guardianParticipationStatus:participation.guardianParticipationStatus||null};}).sort(function(a,b){return a.name.localeCompare(b.name,'ar');});
  }
  getAllRooms().forEach(function(r){if(r.closed)return;getConferenceRoomPeopleOnDay(r,undefined,current).forEach(function(person){l.push({name:person.name||gn(person),room:r.number,guardian:person.isChild?(person.guardianFullName||person.guardian||''):null,personId:person.personId||'',guardianPersonId:person.guardianPersonId||'',guardianParticipationStatus:person.guardianParticipationStatus||null})})});
  return l.sort(function(a,b){return a.name.localeCompare(b.name,'ar')});
}
