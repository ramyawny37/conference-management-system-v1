function assignedNames(){
  var current = getCurrentConference();
  if (!current) return {};
  var n={};
  (current.transports || []).forEach(function(t){
    (t.seats || []).forEach(function(s){
      if(s.name&&s.type!=='child_shared'&&s.type!=='infant')n[s.name]=true;
    });
  });
  return n;
}

function activeGuests(day){ // day=undefined means current/total
  var current = getCurrentConference();
  if (!current) return { adults: [], children: [] };
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
  getAllRooms().forEach(function(r){if(r.closed)return;getConferenceRoomPeopleOnDay(r,undefined,current).forEach(function(person){l.push({name:person.name||gn(person),room:r.number,guardian:person.isChild?(person.guardianFullName||person.guardian||''):null,personId:person.personId||'',guardianPersonId:person.guardianPersonId||'',guardianParticipationStatus:person.guardianParticipationStatus||null})})});
  return l.sort(function(a,b){return a.name.localeCompare(b.name,'ar')});
}
