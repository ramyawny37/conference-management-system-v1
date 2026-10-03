(function (global) {
  'use strict';

  const RETIRED_STATUS = 'conference_role_membership_retired';

  function result() {
    return Promise.resolve({
      ok: false,
      status: RETIRED_STATUS,
      data: null,
      error: null,
    });
  }

  function getState() {
    return {
      status: RETIRED_STATUS,
      role: null,
      canManageMembers: false,
      canSync: false,
      canResolveConflicts: false,
      canAcquireLock: false,
    };
  }

  global.ConferenceMembersService = Object.freeze({
    RETIRED_STATUS,
    getCurrentAccess: result,
    listMembers: result,
    lookupUser: result,
    addMember: result,
    changeRole: result,
    removeMember: result,
    addManager: result,
    removeManager: result,
    getState,
    resetForTests: function resetForTests() {
      return { ok: true, status: 'reset' };
    },
  });
})(window);
