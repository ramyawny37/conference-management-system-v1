# P6B0 canonical Conference-core read and Edge exposure

`get_conference_core` is the single protected hydration operation for canonical
Conference metadata. It requires exact-resource `conference.access.view`
authority and a validated Platform device authorization, then reads the existing
`public.conferences` row. Completed Conferences remain readable; deleted and
unknown Conferences return `CONFERENCE_CORE_NOT_FOUND`.

The response contains `conferenceId`, `organizationId`, `name`, `startDate`,
`endDate`, `status`, `completedAt`, `revision`, `createdAt`, `updatedAt`,
`updatedBy`, `days`, `nights`, and `schedule`. Days, nights, and schedule are
derived from the canonical dates and are not stored separately.

The operation is inserted into
`platform_private.route_canonical_conference_operation`. The existing outer
Platform dispatcher remains the only session-validation and execution boundary.
Both existing Edge endpoints allow and forward the current P3-P5 canonical
operation names; they contain no Conference business logic.

Direct execution of the read function remains revoked from PUBLIC, `anon`,
`authenticated`, and `service_role`. P6B0 adds no browser table read, frontend
state, snapshot compatibility path, dispatcher, or persistence mechanism.
