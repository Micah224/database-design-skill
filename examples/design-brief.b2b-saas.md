# Database design brief

Generated 2026-09-19 from 91 answered questions by 18 rules. Every recommendation lists the answers that drove it and its source; challenge any line without one.

## 1. Conflicts and risks in the answers

No conflicts. That is the intended state and it is rare on a first pass.

## 2. Recommended stack

Primary, alternative, and the condition that should make you switch.

### 2.1 Primary operational datastore

- **Primary:** PostgreSQL 18 — One PostgreSQL cluster as the single source of truth for entities, identity, roles and money. Everything else in this report is a sidecar to it, not a replacement for it.
- **Alternative:** A managed MySQL 8.4 LTS — A reasonable alternative only where your team, tooling and hosting are already built around it.
- **Switch when:** Choose MySQL over PostgreSQL only for an existing-expertise or existing-platform reason. There is no capability in this report that MySQL provides and PostgreSQL does not, and several — row-level security, exclusion constraints, ltree, rich index types — run the other way.

**Why, from the answers:**

- Default position: a relational engine with transactions, constraints and row-level security is the only sane place to put identity, roles and money.
- A3: multi-tenant isolation is far easier to enforce in an engine with row-level security.
- L1: a small team should run one database well rather than four badly.

> Source: PostgreSQL 18 release notes and documentation (released 25 September 2025; 18.6 current as at August 2026). PostgreSQL 18 added non-overlapping PRIMARY KEY and UNIQUE constraints via WITHOUT OVERLAPS and temporal foreign keys via PERIOD. PostgreSQL 19 GA is expected September 2026.

### 2.2 Tenancy and isolation

- **Primary:** Shared schema, tenant_id on every tenant-owned row, enforced by RESTRICTIVE row-level security with FORCE — The policy must be RESTRICTIVE so it ANDs with everything else rather than ORing, and the table must have FORCE ROW LEVEL SECURITY or the owning role silently bypasses it. Set the tenant once per transaction and read it in the policy as (SELECT core.current_tenant()) so the planner hoists it into an InitPlan.
- **Alternative:** A dedicated database or cluster for named large customers — Same schema, different placement, selected by a tenant-placement lookup at connection time.
- **Switch when:** Split a tenant out when it exceeds roughly 100× the median size, or when a contract requires physical isolation. Build the placement indirection first so the split is a configuration change.

**Why, from the answers:**

- A3: shared multi-tenancy.
- Row-level security is a backstop against application bugs, not a substitute for scoping queries in the application.

> Source: PostgreSQL documentation, “Row Security Policies” — table owners bypass row security unless FORCE ROW LEVEL SECURITY is set; referential-integrity checks always bypass row security, which can be used to probe for the existence of hidden rows.
> Source: Supabase, “RLS Performance and Best Practices” — wrapping a function call as (SELECT fn()) lets the planner hoist it to an InitPlan; the published benchmark moves a query from roughly 178,000 ms to about 12 ms.

### 2.3 Search

- **Primary:** PostgreSQL full-text search (tsvector + GIN), with a generated column — Keep the index in the same transaction as the data so it can never be stale. Good to several million documents with sensible ranking.
- **Alternative:** OpenSearch, Elasticsearch or Typesense fed by change data capture — Better relevance tooling, at the cost of a second store that can and will drift.
- **Switch when:** Move out of PostgreSQL when the corpus passes roughly five million documents, or when you need synonyms, per-tenant relevance tuning, or faceting on more than a couple of dimensions.

**Why, from the answers:**

- B7: ranked full-text search was selected.
- A3: whatever you choose must filter by tenant inside the engine, not after it — post-filtering a shared index is how cross-tenant leaks happen.

> Source: PostgreSQL 18 release notes and documentation (released 25 September 2025; 18.6 current as at August 2026). PostgreSQL 18 added non-overlapping PRIMARY KEY and UNIQUE constraints via WITHOUT OVERLAPS and temporal foreign keys via PERIOD. PostgreSQL 19 GA is expected September 2026.

### 2.4 Analytics

- **Primary:** A read replica plus materialised views, refreshed concurrently — Keeps reporting load off the primary without adding a second technology. Refresh on a schedule; never let a dashboard query the write path directly.
- **Alternative:** A columnar extension or an external warehouse — Only when refresh windows stop fitting.
- **Switch when:** Move on when a materialised-view refresh takes longer than the interval you want to refresh it at.

**Why, from the answers:**

- B8: operational dashboards.
- Analytical and transactional workloads have opposite storage requirements. Running both on one row store is the most common cause of “the database got slow and nobody changed anything”.

> Source: ClickHouse documentation — column-oriented MergeTree storage designed for analytical scans; not designed for high-rate point updates or foreign-key integrity.

### 2.5 Event and time-series storage

- **Primary:** Native PostgreSQL range partitioning by time, with BRIN indexes on the timestamp — Range partitioning turns retention into DETACH PARTITION plus DROP TABLE — a metadata operation — instead of a mass DELETE that bloats the table and blocks autovacuum.
- **Alternative:** TimescaleDB hypertables — Automates partition creation and adds columnar compression and continuous aggregates.
- **Switch when:** Adopt Timescale when you are writing partition-management cron jobs by hand, or when storage cost from uncompressed history becomes material.

**Why, from the answers:**

- B4/K2: you have a substantial event or audit stream alongside your entities.

> Source: PostgreSQL documentation, “Table Partitioning” — range partitioning by time makes bulk retention a metadata operation (DETACH/DROP) rather than a mass delete.
> Source: TimescaleDB / Timescale documentation — hypertables partition time-series data inside PostgreSQL, with native compression and continuous aggregates.

### 2.6 Cache and asynchronous work

- **Primary:** No cache yet; a PostgreSQL-backed job queue using SELECT ... FOR UPDATE SKIP LOCKED — One fewer moving part, transactional with your writes, and correct. Adding Redis before you have measured a problem buys you an outage mode you did not have.
- **Alternative:** Redis or Valkey — Add it when a measured hot path justifies it.
- **Switch when:** Add a cache when you have a profiled query that is both hot and tolerant of staleness — in that order.

**Why, from the answers:**

- B2/B3: balanced traffic at 100–2,000 concurrent.
- G3: scoped permission checks are the single most cacheable thing in this design — but only with an explicit version stamp so a revocation invalidates them.

> Source: PostgreSQL 18 release notes and documentation (released 25 September 2025; 18.6 current as at August 2026). PostgreSQL 18 added non-overlapping PRIMARY KEY and UNIQUE constraints via WITHOUT OVERLAPS and temporal foreign keys via PERIOD. PostgreSQL 19 GA is expected September 2026.

### 2.7 Identity: build or buy

- **Primary:** Build the core, and buy the enterprise edge — Own the principal, session and authenticator tables — they are joined to everything else you have. Buy SAML and SCIM federation, which is a long tail of vendor-specific behaviour with no product value in doing it yourself.
- **Alternative:** A hosted identity provider for everything — Fewer things to run, at a per-user cost and with a migration path you must verify before you commit.
- **Switch when:** Buy the whole thing if authentication is not a differentiator and your team is under about five engineers. Build the core if you need identity joined transactionally to your own data — for example, if a permission check must run inside the same transaction as the write it authorises.

**Why, from the answers:**

- L11: you prefer to control the core.
- Whichever you choose, the organisation model stays yours. Identity vendors model a two-level world — tenant, then user. Departments, branches, dated assignments, scoped grants and separation of duties do not exist in any of their data models, so that half of this report is code you will write regardless.
- C3: enterprise SSO was requested. Federation is where buying pays for itself fastest; every enterprise IdP has its own interpretation of the specification.

> Source: OpenID Connect Core 1.0 incorporating errata set 2 (Final, December 2023) — the stable subject identifier is the (iss, sub) pair; email is explicitly not a stable identifier.
> Source: RFC 7643 and RFC 7644 (SCIM 2.0); RFC 9967 defines the SCIM profile for Security Event Tokens (May 2026). In SCIM, deprovisioning is normally active:false, not DELETE.
> Source: RFC 9700 / BCP 240, Best Current Practice for OAuth 2.0 Security (January 2025). Note that “OAuth 2.1” is still an Internet-Draft and is not an RFC.

### 2.8 Authenticators and assurance

- **Primary:** Passkeys as the primary factor, with device-bound passkeys or security keys for administrators — A WebAuthn credential is bound to the origin, so a convincing replica of your login page cannot use it. Enrol two authenticators at registration and make the second one the recovery path.
- **Alternative:** Password plus a number-matched push or TOTP app, with passkeys offered alongside — Acceptable as a transition while passkey coverage builds, and only for populations that are not administrators.
- **Switch when:** Treat the fallback as temporary and instrumented: once passkey enrolment passes about 80% of a population, remove the weaker factor for that population rather than leaving it as a permanent downgrade path an attacker can select.

**Why, from the answers:**

- Phishing resistance comes from origin binding, not from the number of factors. In the 2022 Cloudflare incident, staff entered both their password and a valid TOTP code into an attacker’s site and the attack still failed, because the hardware key would not produce an assertion for the wrong origin.
- Schema consequence: authenticators are rows, not columns. Each row carries its own type, its own creation and last-used timestamps, its own failure counter, and for WebAuthn a credential id of up to 1023 bytes, a COSE public key, a signature counter, a transport list, an AAGUID, and the backup-eligible and backup-state flags. Backup eligibility is fixed for the life of the credential; backup state changes.
- Rate limiting is scoped to the authenticator, not to the whole account: the guidance requires limiting consecutive failed attempts using a specific authenticator on a single subscriber account to no more than 100. Counting failures across the account instead hands any attacker a free lockout weapon against your users.

> Source: NIST SP 800-63B-4, Digital Identity Guidelines: Authentication and Authenticator Management, final 31 July 2025.
> Source: W3C Web Authentication Level 2 — W3C Recommendation, 8 April 2021. Level 3 is a Candidate Recommendation Snapshot dated 26 May 2026 and is not yet a Recommendation.
> Source: Cloudflare, “The mechanics of a sophisticated phishing scam and how we stopped it” (August 2022) — staff entered both credentials and TOTP codes into a phishing site; hardware security keys stopped the attack because the credential is bound to the origin.
> Source: Google Security Blog / “Evaluating login challenges as a defense against account takeover” (2019) — device prompts blocked 100% of automated and 99% of bulk phishing attacks; SMS codes blocked 100% and 96%; knowledge-based challenges performed worst.
> Source: CISA, Implementing Phishing-Resistant MFA — FIDO/WebAuthn and PKI first; app-based OTP and number-matched push next; SMS and voice described as a last resort.

### 2.9 Account recovery

- **Primary:** A second registered authenticator, enrolled at the same time as the first — The cheapest and strongest recovery path there is: it requires no support desk, no identity re-proofing, and no channel weaker than the login itself.
- **Alternative:** Pre-issued single-use backup codes, hashed at rest — Store them hashed like passwords, mark them individually used, and show the remaining count.
- **Switch when:** Add a support-desk path only when you can measure genuine lockouts; then make the re-proofing at least as strong as the original proofing, or you have built a documented bypass.

**Why, from the answers:**

- D4: a second authenticator was selected.
- The guidance is explicit that email SHALL NOT be used as an out-of-band authentication channel: an inbox is not a possession factor, because it is itself reachable with a password from anywhere.

> Source: NIST SP 800-63B-4, Digital Identity Guidelines: Authentication and Authenticator Management, final 31 July 2025.
> Source: NIST SP 800-63A-4, Identity Proofing and Enrollment, final 31 July 2025 — IAL is selected independently of AAL.

### 2.10 Authorization model

- **Primary:** Relationship-based access control, Zanzibar-style — Model access as tuples — this subject has this relation to this object — and let relations compose through the object graph. This is what makes nested folders, shared documents and care-team access tractable, and it answers both “who can see this?” and “what can they see?” from the same index. OpenFGA (a CNCF Incubating project since October 2025) and SpiceDB are the mature open implementations.
- **Alternative:** A closure table in PostgreSQL, plus row-level security — A materialised ancestor table with row-level security gives you the same answers without a second system, as long as the sharing graph stays shallow and your write rate is modest.
- **Switch when:** Stay in PostgreSQL while the sharing graph is a tree you control. Move to a dedicated system when arbitrary users can share arbitrary objects with arbitrary groups — the closure table stops being maintainable at that point. Note that in the published Zanzibar figures the write path is the expensive one: check latency around 3 ms at the median, but write latency around 127 ms.

**Why, from the answers:**

- I1/I3: access depends on the requester’s relationship to the specific record, or on nested containers that inherit access.

> Source: ANSI/INCITS 359-2012 (R2022), Role Based Access Control — Core, Hierarchical, Static SoD and Dynamic SoD components, with sessions as a first-class concept (dynamic separation is defined over roles activated in a session). The model is purely additive: it contains no construct for a negative permission.
> Source: NIST SP 800-162, Guide to Attribute Based Access Control (ABAC) Definition and Considerations — names “role explosion”, and warns that answering who-can-access questions under ABAC “requires significant data retrieval and computation effort”.
> Source: Google, “Zanzibar: Google’s Consistent, Global Authorization System” (USENIX ATC 2019) — over two trillion relation tuples; Check latency p50 around 3 ms, but Write latency p50 around 127 ms. Zookies provide bounded staleness.
> Source: OpenFGA — advanced from CNCF Sandbox to Incubating on 28 October 2025 (announced January 2026), implementing the Zanzibar relationship-tuple model.

### 2.11 Organisation model

- **Primary:** A simple parent reference with a depth check — At your depth, a foreign key to the parent node and an index is the whole design. Do not build a graph model for two levels.
- **Alternative:** Adjacency plus a materialised path — Add it when the depth becomes genuinely variable.
- **Switch when:** Add the materialised path when the tree stops having a fixed number of levels, or when a traversal appears in a request path.

**Why, from the answers:**

- F3: you must reconstruct the structure as at a past date. That means every membership, assignment and edge carries a validity period rather than being updated in place, and that "current" is a view over "valid at now()". This cannot be retrofitted — the history you did not record does not exist.
- Use range types with exclusion constraints so overlapping periods are rejected by the database rather than by a code review. PostgreSQL 18 adds non-overlapping PRIMARY KEY and UNIQUE constraints via WITHOUT OVERLAPS, and temporal foreign keys via PERIOD; on earlier versions, EXCLUDE USING GIST with btree_gist does the same job.
- Employment and assignment are different facts. Someone can be employed by one entity and assigned to another, and both have their own start and end dates. Collapsing them into one row makes secondments, transfers and cover impossible to represent honestly.

> Source: GBIF engineering benchmark of PostgreSQL hierarchy strategies — on ~264,000 descendants, recursive adjacency ≈ 2,080 ms, ltree ≈ 512 ms, integer-array materialised paths ≈ 378 ms; a hybrid of adjacency for writes and a materialised path for reads was recommended.
> Source: Len Silverston, The Data Model Resource Book — the party/role pattern: a party is a person or organisation, and roles are separate, dated relationships rather than columns on the party.
> Source: Ralph Kimball, The Data Warehouse Toolkit — bridge tables and type-2 slowly changing dimensions for reconstructing a hierarchy as at a past date.
> Source: Ed-Fi and OneRoster data standards — employment and assignment are distinct dated associations; a person can be employed by one organisation and assigned to another.

### 2.12 Custom roles and grant ceilings

- **Primary:** Base role plus explicit delta, exactly as you selected — Store base_role_id, an added-permissions set and a removed-permissions set. Render the effective set at read time, and show the administrator the difference from the base whenever they view the role.
- **Alternative:** A fixed set of shipped roles — Fewer support paths, at the cost of every customer whose structure does not match your assumptions.
- **Switch when:** Keep the fixed set while customers look alike. The first enterprise deal that requires a role you do not ship is the trigger, and it is cheaper to have built the registry already.

**Why, from the answers:**

- H2: administrators can only grant what they hold. This prevents privilege escalation by construction and is the cheapest of the safe options.
- H3: the highest privilege is not a standing account. Model break-glass as a role that must be deliberately assumed, with a time limit, a recorded reason and an alert on assumption — never as a boolean column on a user row, which cannot expire and cannot be reviewed.

> Source: ANSI/INCITS 359-2012 (R2022), Role Based Access Control — Core, Hierarchical, Static SoD and Dynamic SoD components, with sessions as a first-class concept (dynamic separation is defined over roles activated in a session). The model is purely additive: it contains no construct for a negative permission.
> Source: NIST SP 800-53 Rev. 5 (Release 5.2.0, August 2025) — AC-5 separation of duties, whose discussion states that “security personnel who administer access control functions do not also administer audit functions”; AC-6 least privilege; AU-9(2) audit record backup onto a physically different system or component; AU-3 audit record content.
> Source: Stripe dashboard user roles — narrowly scoped operational roles are separated (for example refund handling is distinct from dispute handling) rather than combined into one “support” role.

### 2.13 Impersonation and delegation

- **Primary:** Read-only “view as”, with the acting identity always visible in the interface — Support can see what the user sees without being able to act as them, which keeps attribution intact.
- **Alternative:** Full impersonation with the full ceremony — Only if a support workflow genuinely cannot be completed any other way.
- **Switch when:** If you add write impersonation, add the reason, the time limit, the notification and the dual logging in the same change. Retrofitting them is a compliance project.

**Why, from the answers:**

- Schema consequence: every audited action needs two actor columns — the identity whose permissions were used, and the identity who was physically at the keyboard. One column cannot answer “what did support do while impersonating customers last month”, and that is a question you will be asked.

> Source: GitHub Enterprise Server — an administrator impersonating a user must select a reason, the session is recorded in both the enterprise audit log and the impersonated user’s security log, the user is emailed and “you cannot deactivate these emails”, and “a session is limited to one hour”. Documented for Enterprise Server, not Enterprise Cloud.
> Source: Auth0’s user-impersonation endpoint is documented only under the legacy Authentication API path and is absent from the current product surface — i.e. it was not carried forward. Verify current status with Auth0 before relying on this.
> Source: RFC 8693, OAuth 2.0 Token Exchange §4.1 — the act claim expresses delegation with the acting party preserved: “For the purpose of applying access control policy, the consumer of a token MUST only consider the token’s top-level claims and the party identified as the current actor by the act claim.” Nested act claims from earlier delegation steps are disregarded for that purpose.

### 2.14 Audit architecture

- **Primary:** Structured application-level audit events, written in the same transaction, then shipped off-box — Two layers. In-database events give you transactional consistency — an action and its audit record commit or fail together. Shipping them to separately controlled storage, under a different set of credentials, is the only layer that resists a privileged insider.
- **Alternative:** Database triggers capturing row changes — Catches writes that bypass the application, including manual fixes at a psql prompt. Useful as a safety net; poor as a primary record, because a trigger sees column values and not intent.
- **Switch when:** Use both, for different questions. Application events answer “who approved this refund and why”; row triggers answer “what changed in this table at 03:00 during the incident”. Neither answers the other.

**Why, from the answers:**

- K3: the trail must resist privileged insiders. In PostgreSQL an append-only trigger does not achieve that — the documentation is explicit that a table owner is always treated as holding all grant options, so a sufficiently privileged account can drop the trigger. Off-box shipping to storage with different credentials is the control that actually holds, and it is what the audit-record-backup control in the federal catalogue asks for.
- You need before-and-after values on changes. A word of warning about the obvious approach: there is currently no generally maintained generic row-audit extension for PostgreSQL — the widely referenced ones are archived, unreleased since 2022, or explicitly closed to contributions. If you write your own trigger, capture only the changed columns as a delta rather than whole row images, and partition the result. A published account from one engineering team describes a generic audit table that grew to billions of rows and roughly half the database while over 90% of queries touched only the last thirty days.
- Retention: 12 months with 3 immediately available. Partition by time so expiry is a partition drop, and separate "immediately searchable" from "retrievable within a day" — they are different storage tiers and pretending otherwise is what makes long retention expensive.

> Source: NIST SP 800-53 Rev. 5 (Release 5.2.0, August 2025) — AC-5 separation of duties, whose discussion states that “security personnel who administer access control functions do not also administer audit functions”; AC-6 least privilege; AU-9(2) audit record backup onto a physically different system or component; AU-3 audit record content.
> Source: PostgreSQL documentation, “Privileges” — the owner of an object is always treated as holding all grant options, so revoking rights from an owner does not constrain them.
> Source: No generally maintained generic row-audit extension for PostgreSQL is currently available: supa_audit was archived on 16 February 2025 and is read-only; pgMemento’s last release was v0.7.4 in October 2022 (the repository is unmaintained rather than archived); and the 2ndQuadrant audit-trigger repository states that pull requests are not accepted and describes itself as “meant to be a demo more than a ready-to-run extension”.
> Source: Aha! engineering, on removing a generic audit-trigger table that had grown to billions of rows and roughly half the database while over 90% of queries touched only the last 30 days.
> Source: Amazon QLDB reached end of support on 31 July 2025; ledger-style immutability is now generally implemented on general-purpose engines plus object storage with retention locks.

### 2.15 Privacy, consent and retention

- **Primary:** Consent as an append-only event log, per purpose, tied to the exact notice version shown — Store the purpose, the notice version, a hash of the text actually presented, the timestamp, the mechanism, and the source. Current state is a view over the latest event per purpose. A boolean column cannot demonstrate anything, and demonstrating is the legal requirement.
- **Alternative:** A current-state consent table with a separate history table — Two tables that can disagree. Workable, but the log-plus-view shape is strictly better and no harder.
- **Switch when:** If you must keep a current-state table for query speed, generate it from the log rather than writing to both — dual writes drift, and the drift is always discovered during an investigation.

**Why, from the answers:**

- The controller must be able to demonstrate that the data subject consented, and withdrawal must be as easy as giving consent. “As easy” is a design constraint on your interface as much as your schema.
- J3: erasure is required. Erasure and retention will collide — you told us records must be kept for 5–7 years. Resolve it by classifying every table into retention classes: discretionary data is deleted, contractually required data is retained until the contract clock expires, data held for legal claims is retained until that clock expires, audit data is pseudonymised rather than deleted, and the erasure itself is recorded in a tombstone that proves the request was honoured without re-identifying anyone.
- J4: residency. Worth knowing that among the regimes commonly cited for localisation, none of the ones surveyed here impose a blanket in-country storage mandate for ordinary personal data — Kenya’s statute contains a power to prescribe local storage that has not been exercised generally. Most residency requirements you will meet are contractual rather than statutory, which changes what you must build: a region column and a placement rule, not a separate legal entity.
- Breach clock: EU/UK: 72 hours to the supervisory authority; without undue delay to subjects where risk is high. Store the deadline against the breach record along with the rationale for each decision.

> Source: Regulation (EU) 2016/679, Article 7(1) — where processing is based on consent, the controller “shall be able to demonstrate” that the data subject consented; Article 7(3) — withdrawal shall be as easy as giving consent.
> Source: Regulation (EU) 2016/679, Articles 17 (erasure) and 5(1)(e) (storage limitation), read with Article 17(3) exemptions for legal obligations and legal claims.
> Source: Regulation (EU) 2016/679, Art. 33(1) — notify the supervisory authority “without undue delay and, where feasible, not later than 72 hours after having become aware of it”; Art. 34(1) — communicate to the data subject without undue delay where the breach is likely to result in a high risk to rights and freedoms.

### 2.16 Data access layer

- **Primary:** Drizzle ORM with raw SQL for hot paths — Primary recommendation for your language and stated preference.
- **Alternative:** Prisma — Reasonable alternative with a different trade-off between control and convenience.
- **Switch when:** Switch when you find yourself fighting the tool on the queries that matter most — but measure first: most “ORM is slow” findings turn out to be a missing index or a missing join strategy.

**Why, from the answers:**

- L6/L7: TypeScript, ORM for CRUD and SQL for hard paths.
- Whatever you pick, three rules hold. First, the ORM must not own the schema: migrations are reviewed SQL, generated or hand-written, never automatic synchronisation against a model file. Second, row-level security only works if the application connects as a role that does not own the tables — an owning role bypasses row security unless FORCE is set, and even then a superuser does not. Third, every list endpoint needs an explicit join strategy; the N+1 query is not an ORM defect, it is what happens when nobody decides.

> Source: PostgreSQL documentation, “Row Security Policies” — table owners bypass row security unless FORCE ROW LEVEL SECURITY is set; referential-integrity checks always bypass row security, which can be used to probe for the existence of hidden rows.

### 2.17 Availability, backup and migrations

- **Primary:** Managed PostgreSQL with automated backups and point-in-time recovery, and a read replica when reads justify it — Point-in-time recovery is the control that matters. Most data loss is a bad migration or a wrong WHERE clause, not a hardware failure.
- **Alternative:** Self-managed PostgreSQL with pgBackRest and a standby — Cheaper at scale, and it makes you responsible for the recovery you have not yet tested.
- **Switch when:** Self-manage when the managed bill is large enough to fund the operational expertise, and only once you have restored a backup into a scratch environment and timed it.

**Why, from the answers:**

- L4/L5: 99.9%, with a recovery objective of hours.
- A backup you have not restored is a hypothesis. Schedule a restore drill, time it against your stated recovery objective, and record the result — the gap between the objective and the measurement is the number that matters.
- Migrations: expand and contract. Add the new column, backfill in batches, dual-write, switch reads, then drop the old column in a later release. Build indexes CONCURRENTLY. Set a short lock_timeout on the migration role so a blocked DDL statement fails fast instead of queuing behind every query in the system.

> Source: PostgreSQL 18 release notes and documentation (released 25 September 2025; 18.6 current as at August 2026). PostgreSQL 18 added non-overlapping PRIMARY KEY and UNIQUE constraints via WITHOUT OVERLAPS and temporal foreign keys via PERIOD. PostgreSQL 19 GA is expected September 2026.

### 2.18 Domain-specific requirements

- **Primary:** Model the domain facts as tables with periods, not as flags or role names — Section X and the staff operating-condition answers do not change the engine or the authorization model; they change what the schema must contain. The checklist below carries each as a concrete table or constraint.
- **Alternative:** Defer them to application logic — Faster to ship and invisible to auditors; every one of these has been the subject of an incident somewhere.
- **Switch when:** Put a domain fact in the schema the moment more than one code path needs to agree on it — a limit, a licence expiry, a care relationship, a roster window.

**Why, from the answers:**

- Domain answers produced checklist items; see section 3 of this brief.

> Source: NIST SP 800-53 Rev. 5 (Release 5.2.0, August 2025) — AC-5 separation of duties, whose discussion states that “security personnel who administer access control functions do not also administer audit functions”; AC-6 least privilege; AU-9(2) audit record backup onto a physically different system or component; AU-3 audit record content.

## 3. What the schema must contain

Each item exists because an answer requires it. Map each to a part of `assets/reference-schema.sql` via `references/schema-guide.md`.

### Identity and accounts

- [ ] **core.authenticator** — One row per credential per person. Never a single mfa_secret column. Include the WebAuthn credential record fields and a per-row failure counter.
- [ ] **core.session** — Records the assurance level actually achieved, whether user verification was satisfied, when it was satisfied, and the IdP session id if federated — so back-channel logout can find it.
- [ ] **Signature-counter handling that tolerates zero** — An authenticator may legitimately return a signature counter of 0, and synced-passkey providers are widely reported to do so (neither Apple nor Google documents it, so treat it as an observation). A naive “reject if the new counter is not greater than stored” check then rejects those users. Only enforce monotonicity when the stored counter is already greater than zero.
- [ ] **Guest membership class** — A membership with reduced default visibility. One principal, many memberships — never one account per tenant.
- [ ] **core.principal** — One table for every kind of actor — customers, staff, service accounts. Separate tables for “users” and “admins” is the mistake that makes cross-cutting queries and audit impossible.
- [ ] **Account status as an enum, not a boolean** — Pending verification, active, suspended, locked, deprovisioned and anonymised are six different states with six different behaviours. is_active collapses them and loses the reason.
- [ ] **core.identity_link** — One row per external identity, unique on (issuer, subject). Never join federated identities on email — email is mutable and reassignable, and the issuer-plus-subject pair is the only stable key.
- [ ] **Partial unique index on the login handle** — Unique where the account is not anonymised, so a closed account does not reserve an address forever and a returning customer can register again.
- [ ] **core.invitation** — Invitations are their own object with an expiry, a single-use token hash, an issuer and a scope. Not a user row in a pending state.

### Roles and permissions

- [ ] **core.permission** — A registry of (action, resource_type) with a stable key, a human description, and a flag for whether the permission is dangerous. Not a string enum in code.
- [ ] **core.role** — tenant_id NULL means a system role. A custom role records the base role it derives from, so shipped roles can be improved without rewriting every customer’s copy.
- [ ] **core.role_assignment** — (principal, role, scope node, inheritable, validity period) plus who granted it, why, and under what approval.
- [ ] **core.role.max_grantable / core.role_grantable** — Whatever ceiling you choose, it must be stored and enforced server-side, not implied by which buttons the interface renders.
- [ ] **Mandatory end date on contractor/partner grants** — valid upper bound NOT NULL for contractor principals, enforced at grant time.
- [ ] **core.effective_permissions(principal, scope, at)** — One function that resolves grants, role inheritance, scope inheritance and denies. Every call site uses it. The moment two code paths compute permissions differently, they disagree, and the disagreement is a vulnerability.

### Organisation structure

- [ ] **core.org_node / core.org_edge** — Nodes carry a type, a jurisdiction and an operating period. Edges carry the hierarchy they belong to and their own validity period.
- [ ] **Validity periods on every assignment** — tstzrange plus an exclusion constraint. “Current” becomes a view, not a table.

### Privacy and consent

- [ ] **privacy.purpose + privacy.notice** — Versioned notices with a content hash; purposes with a lawful basis, a retention period and a named owner.
- [ ] **privacy.consent_event** — Append-only. Purpose, notice version, presented hash, mechanism, timestamp, source. Current state is a view.
- [ ] **privacy.subject_request + privacy.erasure_tombstone** — The request, its statutory deadline and its outcome; and proof that an erasure happened without retaining what was erased.
- [ ] **Retention class on every table** — Partition or tag by retention class so expiry is executable rather than aspirational.

### Audit and evidence

- [ ] **Range-partitioned event tables** — Partition on the timestamp that your retention rule is written against, not on insert time if they differ.
- [ ] **core.impersonation_session** — Actor, subject, reason, approval, start, hard expiry, and a link from every action taken during it.
- [ ] **audit.event** — Partitioned by time. Actor, on-behalf-of actor, action, resource type and id, outcome, source address, request id, tenant, and the assurance level of the session that did it.
- [ ] **Grant history that survives revocation** — A revoked grant must remain visible as a historical fact. Deleting the row destroys the only evidence that the access ever existed.
- [ ] **Point-in-time access query** — You must be able to run “who held permission P over scope S on date D, and who approved it”. Write that query now and keep it as a test — it is the fastest way to discover that your schema cannot answer it.

### Tenancy

- [ ] **core.tenant** — One row per customer organisation, with lifecycle state and placement.
- [ ] **tenant_id on every tenant-owned table** — Not derivable by join. Denormalised deliberately, so the RLS policy is a single column comparison.

## 4. Answers (the audit trail for this design)

| # | Question | Answer | Note |
|---|---|---|---|
| A1 | Which best describes what the system is for? | B2B SaaS sold to organisations |  |
| A2 | Who will hold accounts in the system? | Employees of your business customers; Your own employees |  |
| A3 | Is the system multi-tenant? | Yes — shared schema, tenant_id on every row | Confirmed with the CTO on 2026-09-01: shared schema now, dedicated for enterprise tier later. |
| A4 | What is the worst realistic consequence of a wrong, lost or leaked record? | Serious reputational or competitive damage |  |
| A5 | Does the system do any of these regulated things? | None of the above |  |
| B1 | How many rows will your largest single table hold 24 months after launch? | 1 – 50 million |  |
| B2 | What is the read-to-write ratio on the busiest path? | Mixed — roughly 70:30 to 50:50 |  |
| B3 | Peak concurrent active users or connections at the busiest minute? | 100 – 2,000 |  |
| B4 | Does the dominant data have a time axis — is it a stream of dated events? | Partly — entities plus a large event/audit stream beside them |  |
| B5 | How variable is the shape of your records? | Mostly fixed, plus a handful of optional or customer-specific fields |  |
| B6 | Where are your users, physically? | One region (e.g. EU, West Africa, US) |  |
| B7 | What kind of search do users need? | Ranked full-text search over documents or listings |  |
| B8 | What analytics do you need over this data? | Operational dashboards over recent data |  |
| B9 | What consistency does the core write path require? | Read-committed with explicit locking where it matters |  |
| B10 | Do clients need to work offline and sync later? | No — always online |  |
| C1 | What will end users type into the “username” field? | Email address |  |
| C2 | What is the login policy for staff and internal users? | Company email domain only, with MFA, but local accounts |  |
| C3 | Do your business customers need to bring their own identity provider? | Both, plus SCIM provisioning |  |
| C4 | How strongly must you prove that a user is who they claim to be? | Possession of an email or phone is enough |  |
| C5 | How do accounts come into existence? | Both — public signup for customers, invitation for staff |  |
| C6 | Can one human legitimately hold more than one account? | One account that can hold several roles at once |  |
| C7 | Does anyone ever act on another person’s behalf? | No |  |
| C8 | Which personal attributes will you actually store? | Name and contact only |  |
| C9 | Do you need to know a user’s age or age band? | No |  |
| D1 | What authentication assurance do ordinary end users need? | AAL2 — multi-factor required |  |
| D2 | What assurance do staff, admins and super-admins need? | AAL2, phishing-resistant only |  |
| D3 | Which authenticators will you support? | Password; Passkey, synced across the user’s devices; TOTP authenticator app |  |
| D4 | What happens when a user loses their only authenticator? | A second registered authenticator must be used |  |
| D5 | How long should an ordinary user stay signed in? | A working day |  |
| D6 | How long should a privileged administrative session last? | Up to 1 hour idle, 24 hours absolute |  |
| D7 | Do you need to recognise and manage devices? | Users can list and revoke their own devices and sessions |  |
| D8 | Which actions should force a fresh, stronger authentication? | Granting or changing permissions; Changing email, phone or password |  |
| D9 | How much automated abuse do you expect against sign-up and sign-in? | Normal public-internet background noise |  |
| E1 | Which account self-service capabilities must exist at launch? | Change email address; Change password; Enrol, list and remove authenticators; See active sessions and sign out elsewhere; Download a copy of their data; Delete or close the account; A consent / preference centre with withdrawal |  |
| E2 | How will the system contact users? | Email |  |
| E3 | Do users have a profile that other users can see? | Visible within their own organisation only |  |
| E4 | Do you store payment instruments? | Tokens only — the processor holds the card |  |
| E5 | Do users belong to groups that share access to things? | Yes — nested groups, folders or spaces |  |
| E6 | Do you need plans, entitlements or usage quotas? | Per-seat licensing that must be counted and enforced |  |
| E7 | Do users create content that someone must review or moderate? | No |  |
| F1 | What internal structure exists beyond “admin and user”? | Departments or functions; Project teams or squads |  |
| F2 | How deep does that structure go, and is there more than one of it? | Fixed depth, e.g. region → branch → team |  |
| F3 | Do you need to reconstruct the structure as it stood on a past date? | Yes — historical reconstruction is required |  |
| F4 | Can one person be attached to more than one unit at the same time? | Freely many, with no primary |  |
| F5 | Do units cross national or legal-entity boundaries? | No |  |
| F6 | Do your customer organisations have their own internal structure that you must model? | Teams or workspaces inside a tenant |  |
| G1 | How many genuinely distinct staff job functions will the system need to distinguish? | 4 – 10 |  |
| G2 | How does a person actually get a role? | An administrator assigns it by hand |  |
| G3 | Are staff permissions scoped to the part of the organisation they work in? | Yes — to their own unit only |  |
| G4 | Do staff ever need temporarily elevated rights? | No |  |
| G5 | Which duties must never be held by the same person at the same time? | None |  |
| G6 | Is access tied to a shift, roster or opening hours? | No — access is continuous |  |
| H1 | Can an administrator create new roles, or only use the ones you ship? | Yes — but only as “a shipped role, plus or minus specific permissions” |  |
| H2 | Who is allowed to grant what? | An admin can only grant permissions they hold themselves |  |
| H3 | How should the highest level of access work? | A break-glass role that must be deliberately assumed, time-boxed and alarmed |  |
| H4 | Does support staff need to see or use the product as a specific user? | Read-only “view as” — no actions can be taken |  |
| H5 | Which administrative actions need a second person to approve them? | Granting a privileged role |  |
| H6 | Do you need periodic access reviews? | Yes — a scheduled campaign with recorded attestations |  |
| H7 | What must administrators be able to see? | User and account lists with lifecycle state; Who currently holds which permission, and why; Activity and audit search |  |
| H8 | Do your customers administer their own users? | Yes — each customer has their own administrators |  |
| I1 | What does a permission decision actually depend on? | The person’s role alone; Their role plus the organisational unit of the record; Their relationship to the specific record |  |
| I2 | Do you need to answer “who can access this record?” and “what can this person access?” as fast queries? | Yes — list what a person can see, for their home screen |  |
| I3 | How do users share things with each other? | Through nested folders or spaces that inherit access |  |
| I4 | Do you need explicit denies or exceptions? | No — everything is additive |  |
| I5 | What is the latency budget for a single permission check? | Under 50 ms — a normal request |  |
| I6 | Where should the authorization decision be made? | In the application, with the database as a backstop |  |
| J1 | Which data-protection or security regimes apply to you? | EU GDPR and/or UK GDPR; SOC 2 — customers will ask for the report |  |
| J2 | Do you need to prove, later, that a specific person consented to a specific thing? | Yes — separately per purpose, with independent withdrawal |  |
| J3 | Must you honour deletion requests? | Yes — irreversibly anonymise, keeping records we must retain |  |
| J4 | Is there a data residency requirement? | Only because customers ask for it in contracts |  |
| J5 | How long must core records be kept? | 5 – 7 years |  |
| J7 | Do you understand your breach-notification clock? | Roughly, but it is not rehearsed |  |
| J8 | Do third parties process this data on your behalf? | A few — hosting, email, analytics |  |
| K1 | What must you be able to reconstruct after the fact? | Every sign-in, failure and MFA challenge; Every change to a record, with before and after values; Every permission grant, revocation and role change; Every administrative and configuration action |  |
| K2 | How long must the audit trail be kept, and how much of it must be instantly searchable? | 12 months, with 3 months immediately available |  |
| K3 | Must the audit trail resist tampering by your own privileged staff? | Yes — records must be shipped to separately controlled storage |  |
| K4 | Will you be asked “who had access to this, on this date, and who approved it?” | Routinely — auditors, regulators or customers ask |  |
| L1 | Who will operate this database? | A small team with one person who is comfortable with SQL |  |
| L2 | How will it be hosted? | Managed cloud database service |  |
| L3 | Which platform? | AWS |  |
| L4 | What availability does the business actually need? | 99.9% — under an hour a month |  |
| L5 | How much data may you lose in a disaster, and how quickly must you be back? | An hour of data; back within hours |  |
| L6 | What is the primary application language? | TypeScript / Node |  |
| L7 | What is your position on ORMs? | An ORM for CRUD, raw SQL for the hard paths |  |
| L8 | How disciplined is your schema-change process? | Generated migrations, reviewed in pull requests |  |
| L9 | How price-sensitive is the infrastructure budget? | Normal — value for money |  |
| L10 | How long until this must be in production? | A quarter |  |
| L11 | Would you rather build authentication yourself or buy it? | Build the core, buy enterprise SSO/SCIM as an add-on |  |
| X-B2B1 | What is the largest tenant likely to be, relative to the median? | Up to about 10× the median |  |
| X-B2B2 | Do you need guest or external-collaborator access inside a tenant? | Yes — a distinct guest class with reduced default visibility |  |
| X-B2B3 | How do tenants get deleted or exported? | Other — Export is self-service; deletion is manual with a signed certificate within 30 days (contract clause 14.2). |  |
