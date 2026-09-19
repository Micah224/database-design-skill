# Schema guide: `assets/reference-schema.sql`, part by part

The reference schema is 1,331 lines of PostgreSQL implementing every pattern the rule engine can recommend. It applies cleanly to PostgreSQL 16 and above; `assets/schema-tests.sql` proves 29 assertions about it; the suite runs inside a transaction it rolls back, so it can be re-run on the same database.

It is written for PostgreSQL 16 compatibility on purpose — `EXCLUDE USING GIST` with `btree_gist` rather than PostgreSQL 18's `WITHOUT OVERLAPS` (primary key / unique) and `PERIOD` (foreign keys), `gen_random_uuid()` rather than `uuidv7()` — with comments marking where the newer syntax applies.

**Do not adopt it wholesale.** Take the parts the brief's schema checklist names and delete the rest. A schema with tables you do not need is worse than one missing tables you do: the unused ones still have to be migrated, secured and explained.

## Mapping the checklist to parts

| Checklist group in the brief | Schema part(s) |
|---|---|
| Tenancy | Part 1 (`tenant`), Part 10 (row-level security) |
| Identity and accounts | Part 2 |
| Roles and permissions | Part 3, Part 9 (`effective_permissions`), Part 11 seed |
| Organisation structure | Part 1 (`hierarchy`, `org_node`, `org_edge`), Part 4 (staff, employment, assignment) |
| Privacy and consent | Part 5 |
| Audit and evidence | Part 6, Part 7 (approvals), Part 8 (access reviews) |

## The parts

| Part | What it establishes | The detail worth noticing |
|---|---|---|
| 0 — Extensions, schemas, roles | `pgcrypto`, `btree_gist`, `ltree`, `citext`; schemas `core`/`privacy`/`audit`; roles `app_owner`, `app_runtime`, `app_migrator`, `audit_reader` | The application role does **not** own the tables — an owner bypasses row-level security unless FORCE is set, and a superuser always does. `lock_timeout = 2s` on the migrator so a blocked DDL fails fast instead of queuing behind every query. |
| 1 — Tenancy and the tree | `tenant`, `hierarchy`, `org_node`, `org_edge` | One edge table keyed by hierarchy, with a per-hierarchy single-parent exclusion constraint. Nodes carry a jurisdiction, an operating period and an `ltree` materialised path maintained by trigger (adjacency is the truth; the path is derived). |
| 2 — Identity | `principal`, `identity_link`, `authenticator`, `recovery_code`, `session`, `refresh_token`, `pending_contact_change`, `invitation` | **One** principal table with a six-state status. Federated identity unique on `(issuer, subject)`, never email. Email uniqueness is partial (`status <> 'anonymised'`) so a closed account does not block the address forever. Authenticators are rows with per-row failure counters and the WebAuthn credential fields (`cred_id bytea`, `backup_eligible` immutable, `backup_state` mutable). Sessions record the AAL *achieved* and `uv_satisfied_at` for step-up. Invitations are their own object. |
| 3 — Authorisation | `permission`, `role`, `role_permission`, `role_delta`, `role_hierarchy`, `role_grantable`, `role_assignment`, `role_activation`, `deny_rule`, `sod_constraint` (+`_role`, `_exception`), `delegation`, `impersonation_session` | The assignment row is the unit of privilege: principal × role × scope node, `inheritable`, `active`/`eligible`, a `tstzrange` validity, and full provenance (`granted_by`, `justification`, `approval_id`, `sponsor_id`). Denies are a separate last-evaluated layer. Custom roles are base + delta. Impersonation sessions are capped at one hour by CHECK. |
| 4 — Staff | `staff`, `staff_employment`, `staff_assignment`, `staff_credential` | Employment (who pays) and assignment (where you work) are separate dated facts. Exactly one `primary_base` at any instant and one `manages` per hierarchy — partial exclusion constraints, not booleans. Licences have their own expiry. |
| 5 — Consent and privacy | `notice`, `purpose`, `consent_event`, `consent_current` (view), `proxy_access`, `subject_request`, `erasure_tombstone`, `retention_policy`, `breach`, `breach_notification` | Consent is an append-only event log with a hash-verification trigger against the versioned notice; current state is a view. Purposes carry a lawful basis and a retention class (A–E). Breach notifications carry per-regime deadlines and a NOT NULL `decision_rationale`. |
| 6 — Audit | `event` (range-partitioned), `row_change` (delta, partitioned), `deleted_record` | Append-only trigger + INSERT-only grant, with the caveat that neither constrains an owner — ship off-box for that. The event carries both `actor_id` and `on_behalf_of_id`, the session AAL, and the grant that authorised the action. Row-change logging is attached only to grants and denies. |
| 7 — Approvals | `approval_request`, `approval_decision` | `CHECK (approver_id <> maker_id)` (maker denormalised by trigger). The guard trigger enforces pending state, expiry, payload-hash binding and no decisions from inside an impersonation session; editing an approved payload drops it back to pending (rebind). |
| 8 — Access review | `access_review_campaign`, `access_review_item`, `access_review_attestation` | Snapshot columns, including `snap_last_used_at`, so an attestation records what was reviewed rather than what the live table says now. |
| 9 — Effective permissions | `effective_permissions(principal, scope, at)`, `tenant_permissions_version`, grant-ceiling and SoD triggers, `sod_conflicts` view | One function used by every call site: live assignments → activation for eligible grants → role-hierarchy closure → ltree scope inheritance → unconditional deny check. Returns the assignment that conferred each permission, so "why can this person do this?" is answerable. Any grant change bumps the tenant's permissions version (cache invalidation, offline staleness). |
| 10 — Row-level security | `current_tenant()`, RESTRICTIVE `tenant_isolation` policies, FORCE, ownership of tables **and views** to `app_owner`, `security_invoker` on views | Policies read the tenant as `(SELECT core.current_tenant())` so the planner hoists it into an InitPlan. Views run with their owner's privileges by default, so a superuser-owned view is a back door through RLS — hence `security_invoker = true` and non-superuser ownership (tested). |
| 11 — Seed | 4 hierarchies, 18 permissions, 7 system roles, grantable sets, one SoD constraint, purposes, retention policy | `iam_admin` grants roles but cannot read the audit log; `security_admin` reads the audit log but cannot grant (NIST SP 800-53 AC-5). `platform.break_glass` is a **role**, eligible-only, never a boolean. |
| 12 — Proof queries | Six commented queries | Point-in-time approver set; privileged grants with approver; live SoD conflicts; impersonated actions; consent proof with exact wording; deprovisioning lag. Keep them as integration tests. |

## Running the tests

```bash
createdb reftest
psql -d reftest -v ON_ERROR_STOP=1 -f assets/reference-schema.sql
psql -d reftest -f assets/schema-tests.sql 2>&1 | grep -E "PASS|FAIL"
```

The run is wrapped in a transaction that is rolled back, so it is re-runnable. Expected: 29 PASS, 0 FAIL.

## Adapting it

- **Single-tenant system?** Keep `tenant_id` anyway (nullable, one value). Dropping it is the one change that costs a quarter to reverse.
- **No staff tier?** Drop Part 4 and the `staff*` references; keep `org_node` if you have any location or department scoping at all.
- **No consent basis?** Keep `privacy.purpose` and `retention_policy` (they make retention executable); drop `consent_event`, `notice`, `consent_current`.
- **Not multi-hierarchy?** Keep one row in `hierarchy`; the schema costs nothing extra and the second hierarchy always arrives.
- **Relationship-based access (documents, folders, care teams)?** The schema gives you roles, scopes and denies. Add a relation-tuple table or an external ReBAC service (OpenFGA / SpiceDB) beside it; do not try to express sharing as roles.
- **Different engine?** The patterns transfer; the exclusion constraints, `ltree` and row-level security do not. On MySQL you will enforce overlap and scope inheritance in application code — the brief will have told you that if it applies.
