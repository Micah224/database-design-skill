# Decision rules

The answer-to-recommendation map: 74 rules across 18 decision areas. Each gives one primary choice, one alternative, and the condition under which to switch. `scripts/recommend.js` applies these deterministically; this file is for reading and review.

Evidence keys resolve in `evidence.md`.

## Primary datastore

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| B10 = full offline writes | PostgreSQL on the server + SQLite on each device, with an explicit versioned sync protocol | A sync-first platform (ElectricSQL, PowerSync, CouchDB/PouchDB) | Switch to a sync platform once hand-rolled conflict resolution passes a few hundred lines, or two clients can legitimately edit the same row | PG-DOCS / SQLITE |
| L2 = serverless runtime | Serverless-native managed PostgreSQL (Neon, Aurora Serverless v2, Cloud SQL/AlloyDB) behind a pooler | Provider-native store (DynamoDB, Firestore, D1) | Only if access patterns are genuinely key-value and you will never need a join, a report or a foreign key | PG-DOCS |
| B1 = tiny AND A3 = single AND B3 = <100 concurrent AND not regulated AND one country | PostgreSQL 18 | SQLite in WAL mode, embedded | SQLite stops being viable at a second writing app node, a network filesystem, or per-role row filtering in the database | SQLITE |
| B5 = polymorphic AND money is not involved | PostgreSQL with jsonb for the variable part, columns for the stable part | MongoDB | Move to a document store when under ~40% of fields are shared across records AND no query ever relates two record types | MONGO |
| B6 = global AND L4 >= 99.95% AND money/strict consistency | PostgreSQL 18 | Distributed SQL (CockroachDB, YugabyteDB, Spanner) | When a single write region cannot meet latency in a second region, or regional write outage becomes commercially unacceptable | PG-DOCS |
| B1 in (large, huge) AND B4 = dominant event stream | PostgreSQL 18 for entities | PostgreSQL + ClickHouse for the event stream | Split when the event table alone passes ~1 billion rows, or analytical scans interfere with transactional latency | CLICKHOUSE |
| Default | PostgreSQL 18 | Managed MySQL 8.4 LTS | Only for an existing-expertise or existing-platform reason; no capability in this matrix is MySQL-only, and several are PostgreSQL-only | PG-DOCS |
## Tenancy

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| A3 = single | One dataset, but with an organisational scope column from day one | Add tenant_id anyway | Add tenant_id now if any commercial scenario has a second organisation using the system | PG-RLS |
| A3 = schema-per-tenant | Schema-per-tenant on one cluster; route by search_path at checkout | Shared schema + tenant_id + RESTRICTIVE RLS | Move to shared past roughly 500-1,000 tenants: migrations become N-schema batch jobs and catalogue overhead dominates | PG-RLS |
| A3 in (shared, hybrid, unsure) | Shared schema, tenant_id on every row, RESTRICTIVE RLS with FORCE, tenant read as (SELECT fn()) for InitPlan hoisting | Dedicated database for named large customers, chosen by a placement lookup | Split a tenant at ~100x median size or on a contractual isolation requirement; build the placement indirection first | PG-RLS / SUPABASE |
## Search

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| B7 = prefix/substring | PostgreSQL B-tree + pg_trgm GIN | A dedicated search engine | When relevance ordering, not matching, becomes the complaint | PG-DOCS |
| B7 = ranked full text | PostgreSQL tsvector + GIN on a generated column | OpenSearch / Elasticsearch / Typesense via CDC | Past roughly 5 million documents, or when synonyms, per-tenant tuning or multi-dimension faceting are required | PG-DOCS |
| B7 = typo tolerance / facets / synonyms | Dedicated engine (Typesense or Meilisearch small, OpenSearch or Elasticsearch large) | PostgreSQL FTS + pg_trgm | Stay in PostgreSQL under a few hundred thousand documents if 'good enough ordering' is truly acceptable | PG-DOCS |
| B7 = semantic / vector | pgvector with an HNSW index, inside PostgreSQL | Dedicated vector store (Qdrant, Weaviate, Milvus) | Past roughly 10-50 million vectors, or when high-QPS filtered ANN stops meeting latency | PGVECTOR |
## Analytics

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| B8 = operational dashboards | Read replica + materialised views refreshed concurrently | Columnar extension or external warehouse | When a refresh takes longer than the interval you want to refresh at | CLICKHOUSE |
| B8 = heavy aggregation | ClickHouse (or DuckDB over Parquet at smaller volume) fed by CDC | Managed warehouse (BigQuery, Snowflake, Redshift) | Warehouse when analytics is a scheduled business function; ClickHouse when sub-second aggregation is user-visible | CLICKHOUSE |
| B8 = warehouse already planned | Log-based CDC (Debezium or native) into the warehouse | Scheduled batch extracts | Batch is only correct while every table is append-only or soft-deleted; the first hard delete makes it wrong, not merely stale | CLICKHOUSE |
## Event storage

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| B4 = dominant AND B1 in (large, huge) | TimescaleDB hypertables, or ClickHouse if the stream is the product | Native PostgreSQL range partitioning + BRIN | Native partitioning suffices until compression ratio or continuous aggregates bind, typically past a few hundred million rows per table per year | TIMESCALE |
| B4 = secondary, or long audit retention | Native PostgreSQL range partitioning by time, BRIN on the timestamp | TimescaleDB hypertables | Adopt Timescale when you are hand-writing partition cron jobs, or uncompressed history cost becomes material | PG-PART |
## Cache / async

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| B3 high, or bursty, or read-heavy at scale | Redis or Valkey for cache and rate limiting, plus a queue | Durable log or managed queue (Kafka, SQS, Pub/Sub) | Move off a DB-backed queue past a few thousand jobs/second sustained, or when a second independent consumer needs the same stream | PG-DOCS |
| Otherwise | No cache; PostgreSQL job queue with SELECT ... FOR UPDATE SKIP LOCKED | Redis or Valkey | Add a cache only for a profiled hot path that tolerates staleness | PG-DOCS |
## Identity build/buy

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| J4 = residency required by law, or L2 = on-premises | Self-hosted open source (Keycloak, Ory, Zitadel, Authentik) | Build authentication into the application | Build in-app only while you support a password and one second factor; SAML, SCIM or passkey attestation flips the calculation | OIDC / SCIM |
| L11 = buy, or small team on a short timeline | Hosted IdP (Auth0, Clerk, WorkOS, Firebase, Cognito, Stytch, Supabase Auth) - verify current per-MAU pricing at your expected tier | Self-hosted open source | When per-user cost exceeds the loaded cost of the engineer who would run it, or a contract requires identity inside your perimeter. Verify the export path first: some providers cannot export password hashes at all | OIDC / SCIM |
| Otherwise | Build the core (principal, session, authenticator); buy SAML/SCIM federation | Hosted IdP for everything | Buy it all if authentication is not a differentiator and the team is under ~5 engineers. Build the core if permission checks must run in the same transaction as the write they authorise | OIDC / SCIM / OAUTH-BCP |
## Authenticators

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| D1/D2 phishing-resistant, or money, or safety | Passkeys primary; device-bound passkeys or security keys for administrators | Password + number-matched push or TOTP, with passkeys alongside | Remove the weaker factor for a population once passkey enrolment passes ~80%; a permanent fallback is a downgrade path an attacker selects | NIST-63B / WEBAUTHN / CF-2022 |
| Otherwise | Password (15-char minimum as sole factor, no composition rules, no rotation, breach-list screened) plus a second factor | Passkey-first with password fallback | Go passkey-first as soon as platform mix allows; later migration cost is communication, not engineering | NIST-63B |
| D3 includes SMS | Keep as last-resort fallback only, never sufficient alone for a privileged action | Number-matched push or TOTP | Any money movement, payout change or limit change requires a phishing-resistant factor | CISA / GOOGLE-2019 / FBI-IC3 |
## Recovery

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| D4 in (second authenticator, backup codes) | A second authenticator enrolled at registration | Hashed single-use backup codes | Add a support-desk path only on measured lockouts, and re-proof at least as strongly as at registration | NIST-63B |
| D4 in (email link, SMS, helpdesk, admin) | Require a second authenticator at enrolment and make it the recovery path | Support-desk recovery with re-proofing recorded as an event | Keeping an emailed or texted reset means the account is single-factor for risk purposes regardless of the login screen | NIST-63B / NIST-63A |
## Authorization model

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| I1 includes relationship/assignment, or I3 = nested, AND reverse queries needed | Relationship-based (Zanzibar-style): OpenFGA (CNCF Incubating since Oct 2025) or SpiceDB | Closure table in PostgreSQL + RLS | Stay in PostgreSQL while the sharing graph is a tree you control; move when arbitrary users share arbitrary objects with arbitrary groups | ZANZIBAR / OPENFGA |
| I1 includes attributes/state/clearance/consent AND >2 input kinds | RBAC backbone + policy engine (Cedar, OPA, Cerbos) | Conditions stored as data on the grant, evaluated in the application | Introduce a policy engine when conditions must be changed without a deploy, or enforced by more than one service | CEDAR / NIST-162 |
| G3 scoped, or deep org | Hierarchical RBAC with scoped assignments: (principal, role, scope node, inheritable, valid period) | Flat RBAC + explicit unit filter in every query | If flat, also enforce the unit filter as RLS so a forgotten WHERE is an empty result, not a cross-branch leak | RBAC-359 |
| Small role count, global scope | Core RBAC | Scoped assignments | Adopt scoping at the first 'only for their own branch', 'only until Friday' or 'only while covering' | RBAC-359 |
| I4 requires denies | Denies in a separate, last-evaluated layer where deny always wins | Ordered rules | Never ordered rules. XACML's eight combining algorithms exist because ordering is hard to reason about | XACML / CEDAR |
## Organisation model

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| F2 = multiple overlapping hierarchies | One org_node table + one org_edge table keyed by hierarchy_id, with a per-hierarchy single-parent exclusion constraint | A separate table per hierarchy | Separate tables only if hierarchies have genuinely different node types and never share traversal code | SILVERSTON |
| F2 = arbitrary depth | Adjacency list for writes + materialised ltree path for reads, maintained by trigger | Recursive CTEs over adjacency alone | Benchmark on ~264k descendants: adjacency ~2,080 ms, ltree ~512 ms, integer-array path ~378 ms. Below a few thousand nodes the recursive query is fine | GBIF |
| F2 = flat or fixed depth | Parent reference + depth check | Adjacency + materialised path | Add the path when depth becomes variable or a traversal appears in a request path | GBIF |
| F3 = historical or future-dated | Validity periods (tstzrange) on every assignment, membership and edge; exclusion constraints reject overlap; 'current' is a view | Current-state tables | Not retrofittable. History you did not record does not exist | KIMBALL / ED-FI |
## Custom roles

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| H1 = catalogue or per-tenant | Custom role = base role + explicit added/removed permission delta | Free assembly from the full catalogue | Free assembly only for customers with an identity or security function; base-plus-delta is far easier to support and upgrade | RBAC-359 / STRIPE-ROLES |
| H1 = fixed | Fixed shipped roles, but build the permission registry now | Administrator-defined roles | Build the editor when the second customer asks for a role you do not ship. Build the registry today regardless | RBAC-359 |
| H2 = any admin can grant anything | Add a grant ceiling: an admin may grant only what they hold, or only explicitly grantable roles | Approval on privileged grants | Without a ceiling every administrator is a super-administrator whatever the UI implies | NIST-53 |
## Impersonation

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| H4 = full impersonation | Mandatory reason, one-hour limit, dual logging, non-suppressible email to the user | Read-only 'view as' | Start read-only; add write impersonation only for named workflows that cannot be done otherwise, and instrument usage | GITHUB-IMP / AUTH0-IMP |
| C7 has proxies/delegates | Delegation preserves both identities (RFC 8693 act claim); never share a code path with impersonation | - | A receiver must consider only the top-level claims and the current actor | RFC-8693 |
## Audit

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| K3 = off-box or cryptographic | Structured application events written in the same transaction, then shipped to separately controlled storage | Row-change triggers as a safety net | Use both, for different questions: events answer intent, triggers answer what changed at 03:00 | NIST-53 / PG-PRIV |
| K3 = none or application-level | Structured application events in the same transaction as the action | Background audit stream | Move out of the transaction only with an outbox that preserves the guarantee | NIST-53 |
| K1 includes before/after values | Custom delta-capturing trigger, partitioned | A generic row-audit extension | No generally maintained generic PostgreSQL row-audit extension exists: supa_audit archived Feb 2025, pgMemento last released 2022, 2ndQuadrant audit-trigger closed to PRs | SUPA-AUDIT / AHA |
| K1 includes reads of sensitive records | Log at query-intent level, not per row returned; partition aggressively | Per-row read logging | The most expensive audit requirement there is: read volume is typically 10-100x write volume | HIPAA |
## Privacy

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| J2 = per purpose or versioned | Append-only consent event log: purpose, notice version, hash of text presented, mechanism, timestamp, source; current state is a view | Current-state table + separate history table | If you keep a current-state table for speed, generate it from the log; dual writes drift | GDPR-7 |
| J3 requires erasure AND long retention | Retention classes: discretionary deleted, contractual retained to clock, legal-claims retained to clock, audit pseudonymised, erasure recorded in a tombstone | Hard delete | Hard deletion and multi-year retention cannot both be satisfied; classify or you will breach one of them | GDPR-17 |
| J3 = crypto-shredding | Per-subject key destruction, with a written rationale | Anonymisation in place | Key destruction is a recognised Purge technique for encrypted media, but no EU or UK regulator has endorsed it alone as Article 17 erasure | NIST-88 |
## Data access layer

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| L6/L7 combination | See the language-by-preference map in the questionnaire | Second-choice tool for the same language | Switch when fighting the tool on the queries that matter - but measure first; most 'ORM is slow' findings are a missing index or join strategy | PG-RLS |
| Any | The ORM must not own the schema; the app role must not own the tables (owners bypass RLS unless FORCED); every list endpoint needs an explicit join strategy | - | - | PG-RLS / PG-PRIV |
## Availability

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| L4 >= 99.95% or L5 = zero data loss | Managed PostgreSQL, synchronous replication to a second AZ, continuous archiving for PITR | Asynchronous replication with measured lag | Synchronous costs a round trip per commit; pay it only where a lost committed write is a business incident | PG-DOCS |
| Otherwise | Managed PostgreSQL with automated backups and PITR; read replica when reads justify it | Self-managed with pgBackRest and a standby | Self-manage when the managed bill funds the expertise, and only after timing a real restore | PG-DOCS |
## Domain-specific requirements

| Condition | Primary | Alternative | Switch when | Evidence |
|---|---|---|---|---|
| X-FIN1 = ledger or ledger + materialised balances | Immutable double-entry ledger; balances derived (and materialised, rebuilt from the ledger); money as numeric/scaled integer with a currency column | Mutable balance column | Never: a balance column destroys the evidence of how the balance was reached | PCI-DSS |
| X-FIN2 = limits vary by role / tier / both | Limits as data: limit_rule(scope, subject_type, subject_key, daily, single, effective_from), evaluated at authorisation time | Limits in configuration constants or role names | The first per-customer exception | STRIPE-ROLES |
| X-FIN4 = daily or real-time reconciliation | Reconciliation run + break tables with an owner and a resolution per unexplained difference | A spreadsheet | When unresolved breaks must block close | - |
| X-HLT1 = care relationship / combo | care_relationship(practitioner, patient, role, location, period) joined by the permission check | Role alone | Role alone never answers the clinical access question | FHIR |
| X-HLT2 = break-glass | Eligible clinical break-glass role: activation with mandatory reason, alert, post-hoc review; never blocked | Blocking out-of-relationship access | Blocking is dangerous in an emergency; grant, justify, review | NIST-53 |
| X-HLT3 = per organisation / fine-grained | Consent scope rows per data category x recipient x period, as an input to the permission check | One share flag | A single flag cannot express the cases that arise | FHIR |
| X-B2B1 = 100x skew | Tenant placement indirection built before the first enterprise deal | Shared placement for all | When one tenant is 100x the median | PG-RLS |
| X-B2B2 = guests | Guest membership class; one principal with memberships in many tenants | One account per tenant | Consultants in several tenants reuse credentials if forced to separate accounts | - |
| X-B2B3 = self-service / contractual | Tenant export and deletion path with a certificate | Manual on request | Asked in the first enterprise security review | GDPR-17 |
| X-COM1 = multiple locations | stock_movement ledger per location; on-hand derived | Quantity column | A quantity column cannot represent a transfer in flight | - |
| X-COM2 = physical POS | Device session separate from human session; PIN/badge re-auth; allowed / denied / approval-required permissions | One shared login per till | Accountability at a till cannot depend on remembering to sign out | SHOPIFY |
| X-LOG1 = licence tracked / blocks | staff_credential with its own expiry; expired credential blocks assignment by constraint | Licence number as username or a report | The licence expires; the account does not | CFR-395 |
| X-LOG2 = continuous telemetry | Telemetry in its own time-partitioned table or store; store the events you act on | Telemetry on the work-order row | Positions and readings are a separate storage problem | PG-PART |
| X-EDU1 = term / course bounded | Dated enrolment and teaching associations with validity periods | Permanent class links | Last year's class is a different fact from this year's | ED-FI |
| X-EDU2 = guardian access | proxy_access with capacity guardian and an automatic lapse at the age threshold | Permanent guardian link | Wrong the day the learner reaches the threshold | ED-FI |
| X-GOV1 = statutory schedule | retention_policy rows carrying the schedule authority; disposal as an audited event | Retention as policy text | When more than one person can create a processing purpose | GDPR-17 |
| G6 = roster-bound (soft / hard) | Roster window on the staff assignment; soft = allow, alert, review; hard = enforced in effective_permissions with break-glass override | Ignore rosters | The 2 a.m. emergency call-out is when the system must still work | - |
| G7 = shared terminal with PIN | Device session table + PIN authenticator type with its own failure counter | Shared password | Accountability dies at a shared screen | SHOPIFY |
| G8 = offline permissions | Permissions version + max staleness on cached decision sets; online re-check for dangerous actions | Unbounded cache | A revocation that never reaches the device | ZANZIBAR |
| G9 = contractor expiry / sponsor | Mandatory end date on contractor grants; sponsor_id + scheduled re-attestation | Open-ended grants | Nobody knows who the account belongs to any more | NIST-53 |