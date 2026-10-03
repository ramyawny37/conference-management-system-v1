(function (global) {
  'use strict';

  function isSystemOwner() {
    const administration = global.SystemOwnerAdministrationService;
    if (administration && typeof administration.isCurrentUserSystemOwner === 'function') {
      try {
        return administration.isCurrentUserSystemOwner() === true;
      } catch (_error) {
        return false;
      }
    }
    const access = global.CurrentAccountAccess || global.PlatformAccountAccess || null;
    return Boolean(access && (access.isSystemOwner === true || access.systemOwner === true));
  }

  function canViewDiagnostics() {
    return isSystemOwner();
  }

  function redact(value) {
    if (value === null || value === undefined) return value;
    if (Array.isArray(value)) return value.map(redact);
    if (typeof value !== 'object') return value;
    const output = {};
    Object.entries(value).forEach(([key, entry]) => {
      if (/token|secret|password|credential|session/i.test(key)) return;
      output[key] = redact(entry);
    });
    return output;
  }

  global.DiagnosticsPrivacyPolicy = Object.freeze({
    canViewDiagnostics,
    redact,
  });
})(window);
