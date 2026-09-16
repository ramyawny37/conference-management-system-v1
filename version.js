window.APP_RELEASE = Object.freeze({
  version: '3.5.0',
  name: 'Conference Management System',
  displayName: 'Conference Management System v3.5.0'
});

/* Development visual-foundation bridge.
   Keeps the new Reservations reference isolated from the legacy generated bundle
   until the approved visual shell is ready for functional migration. */
(function(doc){
  if(!doc || !String(window.location.pathname||'').includes('conference-management-system-development-preview')) return;
  var css=doc.createElement('link');
  css.rel='stylesheet';
  css.href='modules/reservations/reservations-visual-source-v2.css?rev=reference-dashboard-v3';
  doc.head.appendChild(css);
  var script=doc.createElement('script');
  script.src='modules/reservations/reservations-reference-dashboard-v3.js?rev=reference-dashboard-v3';
  script.defer=true;
  doc.head.appendChild(script);
})(document);
