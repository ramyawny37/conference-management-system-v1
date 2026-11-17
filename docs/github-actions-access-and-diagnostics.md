# GitHub Actions access and diagnostic runbook

Last verified: 2026-11-17. Scope: `develop` and Development Preview only. Never modify `main`, Production, or Production Supabase while diagnosing Development.

## Working connector route (verified)

Use the connected GitHub app tools directly, rather than treating browser/API/DNS failures as proof that GitHub Actions cannot be read.

1. `mcp__GitHub__fetch_workflow_run_jobs({repo_full_name:"ramyawny37/conference-management-system-v1",run_id:<numeric_run_id>})` returns jobs, their IDs, status and conclusions.
2. `mcp__GitHub__fetch_workflow_job_steps({repo_full_name:"ramyawny37/conference-management-system-v1",job_id:<numeric_job_id>})` returns step summaries.
3. `mcp__GitHub__fetch_workflow_job_logs({repo_full_name:"ramyawny37/conference-management-system-v1",job_id:<numeric_job_id>})` returns the full decoded job log. Read the first real failure, not just the final summary.
4. `mcp__GitHub__fetch_file({repository_full_name:"ramyawny37/conference-management-system-v1",path:"script.js",ref:"develop"})` reads a specific Development file. Use `mcp__GitHub__search_commits` for commit discovery, but do not assume repository-wide search results are scoped to `develop`.
5. Compare the failing job's commit SHA with the actual `develop` head and the Preview deployment's source SHA before making fixes. Run targeted tests, then broader CI, and verify published Preview.

### Verified examples (historical, not latest)

- Run `42867042191` -> job `130008056426` (`validate`, success). Full job log was retrieved on 2026-11-17.
- Run `42808114686` -> job `129802403871` (`production-clean-cutover`, success). Historical **read-only example**; do not rerun or modify Production.
- The connector's `fetch_commit_workflow_runs` is currently restricted to pull-request-triggered runs. An empty response does **not** establish that a push workflow never ran.
- `get_commit_combined_status` may return an empty `statuses` array even when GitHub Actions ran. Do not interpret that as CI PASS or FAIL.

## Confirming the exact Development HEAD (verified)

Call `mcp__GitHub__compare_commits({repo_full_name:"ramyawny37/conference-management-system-v1",base:"develop",head:"develop"})`. Its `base_commit.sha` is the resolved current branch SHA when status is `identical`. To verify a particular commit is still HEAD, compare that SHA to `develop` and check `status`, `ahead_by`, and `behind_by`. Verified on 2026-11-17: `develop` resolved to `e9d386d4ad4aad5281c526e4b4e525128034c7a4` at the time of the check. This is a snapshot, not a permanently current SHA.

## Finding a current run ID

VERIFIED DIRECT CONNECTOR ROUTE (2026-11-17): `mcp__GitHub__fetch({url:"https://api.github.com/repos/ramyawny37/conference-management-system-v1/actions/runs?branch=develop&per_page=20"})`. Parse `result.content` as JSON; read `workflow_runs[]` fields `id`, `head_sha`, `name`, `status`, `conclusion`, `html_url`. This successfully retrieved the actual latest Development run `44108256520` (success, commit `842d5ab5aaea743d41ab6f38b5d9568a7abe3a78`). Use the numeric ID with `fetch_workflow_run_jobs`, then job ID with `fetch_workflow_job_steps` or `fetch_workflow_job_logs`. This connector `fetch` route avoids external browser/DNS restrictions. Do not use untrusted or non-GitHub URLs.

Preferred: obtain the numeric ID from the repository's Actions run listing, or use an authenticated `gh run list --repo ramyawny37/conference-management-system-v1 --branch develop --limit 20 --json databaseId,headSha,status,conclusion,workflowName` where CLI connectivity is available. The GitHub REST equivalent is `GET /repos/ramyawny37/conference-management-system-v1/actions/runs?branch=develop&per_page=20`. Do not fabricate run IDs or assume the historical IDs are current.

The preview repository can be inspected through the same connector `fetch`, e.g. `https://api.github.com/repos/ramyawny37/conference-management-system-development-preview/commits?per_page=3`. Its latest commit was `fb51ee6bdb52753c554bd816f03cec2f7891b5a0` (2026-11-10) at the time of inspection. A successful source validation workflow is **not** proof of a new Preview deployment. Check the actual deployment pipeline and published manifest separately.

If list access fails, retain the working connector route above for any known run/job ID. Report current CI as unverified until an actual current run is retrieved.

## Acceptance

Record: `develop` SHA, run ID, failed job/step and root cause, targeted test results, full CI result, Preview deployment SHA and runtime smoke-test result. Status vocabulary: PASS / FAIL / BLOCKED. Do not declare deployment success from a successful file fetch or source-only regex checks.

Keep fixes canonical, avoid legacy fallback/parallel code paths, and do not touch `main` or Production.
