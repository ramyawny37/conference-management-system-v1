(function (global) {
  'use strict';

  const MESSAGE = 'تتم إدارة الوصول وصلاحيات المؤتمر من نظام صلاحيات المنصة الموحد.';

  function render(container) {
    const target = typeof container === 'string' ? document.querySelector(container) : container;
    if (!target) return false;
    target.innerHTML = `<div class="empty-state"><strong>صلاحيات المؤتمر موحدة</strong><p>${MESSAGE}</p></div>`;
    return true;
  }

  function getState() {
    return Object.freeze({
      role: null,
      canManageMembers: false,
      members: [],
      retired: true,
      message: MESSAGE,
    });
  }

  global.ConferenceMembersUI = Object.freeze({
    render,
    getState,
    refresh: async function refresh(container) {
      render(container);
      return getState();
    },
  });
})(window);
