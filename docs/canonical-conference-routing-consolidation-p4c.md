# P4C canonical Conference routing consolidation

P4C keeps `platform.execute_conference_device_operation(uuid, uuid, bytea,
text, jsonb)` as the single external Platform Conference entry point. It still
enforces the backend boundary, validates the complete approved account/device
session, and installs the transaction-local Phase1C context.

After validation, the outer dispatcher calls the internal
`platform_private.route_canonical_conference_operation(uuid, uuid, bytea, uuid,
text, jsonb)` router. The router owns explicit argument validation and routing
for canonical Conference creation, Conference core mutation, and Conference
participation list/create/status/delete. Its EXECUTE privilege is revoked from
`PUBLIC`, `anon`, `authenticated`, and `service_role`; clients cannot bypass the
outer dispatcher.

Operations outside the canonical router continue to delegate unchanged to
`platform.execute_conference_device_operation_phase1c_core`. That core remains
a temporary compatibility dependency until its consumers reach zero. Unknown
operations therefore retain the legacy core's deterministic rejection.

Future canonical Conference domains extend the internal router. They do not
rebuild the outer session wrapper or copy legacy core code. Before adding a
large Accommodation surface, the router can be split into domain-owned internal
handlers while preserving this single extension point.

This migration changes routing only. It adds no business table, permission,
audit framework, operation ledger, frontend contract, or cross-domain data
behavior. P3A, P3B, and P4B handlers continue to enforce their existing exact
authority and mutation contracts.
