(function (global) {
  'use strict';

  const MESSAGE = 'تتم إدارة الوصول وصلاحيات المؤتمر من نظام صلاحيات المنصة الموحد.';

  function state() {
    return {
      accessStatus: 'retired',
      role: null,
      canManageMembers: false,
      members: [],
      retired: true,
      message: MESSAGE,
    };
  }

  function renderSection() {
    return '<section id="conference_members_section" class="settings-section sync-settings-section conference-members-section">' +
      '<div class="settings-section-title">صلاحيات المؤتمر</div>' +
      '<div id="conference_members_content" class="settings-empty-state">' + MESSAGE + '</div>' +
      '</section>';
  }

  function retired() {
    return Promise.resolve({ ok: false, status: 'conference_role_membership_retired' });
  }

  global.ConferenceMembersUI = Object.freeze({
    renderSection,
    refresh: retired,
    lookup: retired,
    addMember: retired,
    changeRole: retired,
    removeMember: retired,
    addManager: retired,
    removeManager: retired,
    getAccessState: state,
    getState: state,
    resetForTests: function resetForTests() {
      return { ok: true, status: 'reset' };
    },
  });
})(window);
