(function (global) {
  'use strict';

  const RETIRED_STATUS = 'conference_role_membership_retired';

  function retiredResult() {
    return {
      ok: false,
      status: RETIRED_STATUS,
      role: null,
      canManageMembers: false,
      canSync: false,
      canResolveConflicts: false,
      canAcquireLock: false,
      members: [],
    };
  }

  async function getMyAccess() {
    return retiredResult();
  }

  async function listMembers() {
    return retiredResult();
  }

  async function manageMember() {
    return retiredResult();
  }

  global.ConferenceMembersService = Object.freeze({
    RETIRED_STATUS,
    getMyAccess,
    listMembers,
    manageMember,
  });
})(window);
