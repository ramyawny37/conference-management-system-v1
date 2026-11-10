# Canonical Production Replacement — Executed State

Status: CUTOVER EXECUTED — infrastructure/runtime acceptance complete; first business-data browser smoke remains.
Repository: ramyawny37/conference-management-system-v1
Current source baseline before this documentation commit: main == develop at 799e982c71b9da7418f2c02851f9663d891fcebf
Production Supabase: mpezfbvcdfxpgflehuot
Development Supabase: gppwltrifgfxrkzvvxoe

## Executed decisions
- Production was replaced with the canonical application architecture.
- No Development sample records were copied into Production.
- A new Production owner and approved device were bootstrapped through the canonical security lifecycle.
- Production frontend runtime selects the Production Supabase project outside the Development Preview path.
- Six Production Edge Functions are active.
- Warehouse is not part of the current launch problem. Its prior operational data was accidentally cleared during post-cutover verification; the destructive migration was removed from source and must not be replayed. No fabricated restoration is permitted.

## Runtime acceptance already proven
- Canonical clean bootstrap / Production database cutover: PASS.
- Production owner: 1 active owner.
- Device lifecycle: 1 approved active device; 0 pending.
- Warehouse read-session effective-permission cutover: PASS.
- First-system-bootstrap invariant cutover: PASS for future clean bootstraps.
- Production Edge error inspection after the fixes: no inspected 4xx/5xx/error events.
- Conference and generic device dispatchers remain service-role execution boundaries; direct anon/authenticated execution is not granted.

## Business-data state
At the latest verification: conferences 0; reservations events 0; bookings 0; payments 0. This is the intended clean starting state for conference/reservations business data.

## Remaining acceptance gate
A real browser/device-session smoke is still required before calling the complete product flow PASS:
1. Create the first event/conference through the Production UI.
2. Register a person and booking using the canonical identity flow.
3. Record payment and verify immediate UI/report propagation without manual refresh.
4. Exercise apology/cancellation and later refund through the single settlement path.
5. Verify apologized exclusion from active/completion counts while preserving history and rebooking eligibility.
6. Exercise accommodation including guardian/child lifecycle and automatic extra-bed behavior.
7. Exercise transport and cleanup on apology/delete.
8. Verify event-isolated financial and operational reports.

Do not perform these writes with direct SQL. They must pass through the approved browser device session and canonical Edge/RPC dispatch path.

## Cleanup policy for smoke data
Synthetic financial history is immutable by design. A booking can transition to deleted through the canonical lifecycle, but its financial/cancellation history is intentionally preserved. Therefore do not create synthetic Production financial transactions merely to obtain a green smoke test and then attempt to erase them. Use the first real event/booking for final financial acceptance, or explicitly designate a disposable Production test event whose retained audit history is acceptable.

## Release/CI status
No GitHub combined status or workflow run is currently visible for the final correction SHA. Runtime verification is PASS where stated above; CI must not be reported as PASS until a run/status exists.

## Non-negotiable architecture
- One canonical path only; no Legacy fallback or parallel writer.
- No React path.
- Events remain isolated from each other in reservations, people, accounting and reports.
- Do not change a stable module merely because it contains data.
