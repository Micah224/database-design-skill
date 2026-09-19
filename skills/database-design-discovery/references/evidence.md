# Evidence register

Every source the rule engine cites, by key. The `recommend.js` output prints the full text of each; this file is the index. Evidence current as at 18 August 2026 — standards status, regulator guidance and product lifecycles change, so re-check anything you intend to quote.

**Two entries are marked unverified** (Nigeria GAID Art. 33 wording; PCI DSS 10.2.2/10.5.1 text) because the primary documents could not be retrieved during the research pass. Treat them as reported, not confirmed.

## Identity and authentication

| Key | Source |
|---|---|
| `nist63` | NIST SP 800-63-4 (base volume), final 31 July 2025 — xAL components are chosen separately, not as a bundle. |
| `nist63a` | NIST SP 800-63A-4, Identity Proofing and Enrollment, final 31 July 2025 — IAL is selected independently of AAL. |
| `nist63b` | NIST SP 800-63B-4, Digital Identity Guidelines: Authentication and Authenticator Management, final 31 July 2025. |
| `webauthn` | W3C Web Authentication Level 2 — W3C Recommendation, 8 April 2021. Level 3 is a Candidate Recommendation Snapshot dated 26 May 2026 and is not yet a Recommendation. |
| `ctap` | FIDO Alliance CTAP 2.3 — Proposed Standard, 26 February 2026. A CTAP 2.3.1 Working Draft dated 29 May 2026 also exists, so 2.3 is the latest Proposed Standard rather than the latest document. |
| `google19` | Google Security Blog / “Evaluating login challenges as a defense against account takeover” (2019) — device prompts blocked 100% of automated and 99% of bulk phishing attacks; SMS codes blocked 100% and 96%; knowledge-based challenges performed worst. |
| `cf22` | Cloudflare, “The mechanics of a sophisticated phishing scam and how we stopped it” (August 2022) — staff entered both credentials and TOTP codes into a phishing site; hardware security keys stopped the attack because the credential is bound to the origin. |
| `cisa` | CISA, Implementing Phishing-Resistant MFA — FIDO/WebAuthn and PKI first; app-based OTP and number-matched push next; SMS and voice described as a last resort. |
| `fbic3` | FBI Internet Crime Complaint Center annual reports track SIM-swap complaints and losses, which is why NIST treats the public telephone network as a restricted channel. |
| `rfc9700` | RFC 9700 / BCP 240, Best Current Practice for OAuth 2.0 Security (January 2025). Note that “OAuth 2.1” is still an Internet-Draft and is not an RFC. |
| `oidc` | OpenID Connect Core 1.0 incorporating errata set 2 (Final, December 2023) — the stable subject identifier is the (iss, sub) pair; email is explicitly not a stable identifier. |
| `scim` | RFC 7643 and RFC 7644 (SCIM 2.0); RFC 9967 defines the SCIM profile for Security Event Tokens (May 2026). In SCIM, deprovisioning is normally active:false, not DELETE. |
| `rfc8693` | RFC 8693, OAuth 2.0 Token Exchange §4.1 — the act claim expresses delegation with the acting party preserved: “For the purpose of applying access control policy, the consumer of a token MUST only consider the token’s top-level claims and the party identified as the current actor by the act claim.” Nested act claims from earlier delegation steps are disregarded for that purpose. |
| `auth0imp` | Auth0’s user-impersonation endpoint is documented only under the legacy Authentication API path and is absent from the current product surface — i.e. it was not carried forward. Verify current status with Auth0 before relying on this. |
| `ghimp` | GitHub Enterprise Server — an administrator impersonating a user must select a reason, the session is recorded in both the enterprise audit log and the impersonated user’s security log, the user is emailed and “you cannot deactivate these emails”, and “a session is limited to one hour”. Documented for Enterprise Server, not Enterprise Cloud. |

## Authorization

| Key | Source |
|---|---|
| `rbac` | ANSI/INCITS 359-2012 (R2022), Role Based Access Control — Core, Hierarchical, Static SoD and Dynamic SoD components, with sessions as a first-class concept (dynamic separation is defined over roles activated in a session). The model is purely additive: it contains no construct for a negative permission. |
| `nist162` | NIST SP 800-162, Guide to Attribute Based Access Control (ABAC) Definition and Considerations — names “role explosion”, and warns that answering who-can-access questions under ABAC “requires significant data retrieval and computation effort”. |
| `nist53` | NIST SP 800-53 Rev. 5 (Release 5.2.0, August 2025) — AC-5 separation of duties, whose discussion states that “security personnel who administer access control functions do not also administer audit functions”; AC-6 least privilege; AU-9(2) audit record backup onto a physically different system or component; AU-3 audit record content. |
| `zanzibar` | Google, “Zanzibar: Google’s Consistent, Global Authorization System” (USENIX ATC 2019) — over two trillion relation tuples; Check latency p50 around 3 ms, but Write latency p50 around 127 ms. Zookies provide bounded staleness. |
| `cedar` | AWS Cedar policy language — forbid always overrides permit regardless of order, and policy templates express scoped grants without generating a role per scope. |
| `xacml` | OASIS XACML 3.0 — eight rule/policy combining algorithms and an explicit Indeterminate outcome; ordering matters, which is precisely why deny-overrides is the safe default. |
| `openfga` | OpenFGA — advanced from CNCF Sandbox to Incubating on 28 October 2025 (announced January 2026), implementing the Zanzibar relationship-tuple model. |
| `spicedb` | SpiceDB (AuthZed) — open-source Zanzibar implementation with consistency tokens. |
| `cerbos` | Cerbos — a stateless policy decision point; policies are versioned files, scoped, with most-specific-wins resolution. |
| `avp` | AWS Verified Permissions service quotas — 200 requests per second per policy store for IsAuthorized and IsAuthorizedWithToken (adjustable; the batch APIs are 30 per second), and a non-adjustable limit of 100 transitive parents in the entity hierarchy, aggregated across principals, actions and resources. |

## PostgreSQL behaviour and performance

| Key | Source |
|---|---|
| `pgrls` | PostgreSQL documentation, “Row Security Policies” — table owners bypass row security unless FORCE ROW LEVEL SECURITY is set; referential-integrity checks always bypass row security, which can be used to probe for the existence of hidden rows. |
| `pgpriv` | PostgreSQL documentation, “Privileges” — the owner of an object is always treated as holding all grant options, so revoking rights from an owner does not constrain them. |
| `pgpart` | PostgreSQL documentation, “Table Partitioning” — range partitioning by time makes bulk retention a metadata operation (DETACH/DROP) rather than a mass delete. |
| `supabase` | Supabase, “RLS Performance and Best Practices” — wrapping a function call as (SELECT fn()) lets the planner hoist it to an InitPlan; the published benchmark moves a query from roughly 178,000 ms to about 12 ms. |
| `gbif` | GBIF engineering benchmark of PostgreSQL hierarchy strategies — on ~264,000 descendants, recursive adjacency ≈ 2,080 ms, ltree ≈ 512 ms, integer-array materialised paths ≈ 378 ms; a hybrid of adjacency for writes and a materialised path for reads was recommended. |
| `pgdocs18` | PostgreSQL 18 release notes and documentation (released 25 September 2025; 18.6 current as at August 2026). PostgreSQL 18 added non-overlapping PRIMARY KEY and UNIQUE constraints via WITHOUT OVERLAPS and temporal foreign keys via PERIOD. PostgreSQL 19 GA is expected September 2026. |
| `pgvector` | pgvector documentation — HNSW and IVFFlat indexes for approximate nearest-neighbour search inside PostgreSQL. |
| `timescale` | TimescaleDB / Timescale documentation — hypertables partition time-series data inside PostgreSQL, with native compression and continuous aggregates. |
| `sqlite` | SQLite documentation, “Appropriate Uses For SQLite” and “Well-Known Users” — recommended for embedded, edge and single-writer workloads; write concurrency is serialised at the database level even in WAL mode. |
| `mongo` | MongoDB documentation on multi-document ACID transactions (available since 4.0 for replica sets, 4.2 for sharded clusters) and on the document model’s fit for variable-shape data. |
| `ch` | ClickHouse documentation — column-oriented MergeTree storage designed for analytical scans; not designed for high-rate point updates or foreign-key integrity. |
| `supaaudit` | No generally maintained generic row-audit extension for PostgreSQL is currently available: supa_audit was archived on 16 February 2025 and is read-only; pgMemento’s last release was v0.7.4 in October 2022 (the repository is unmaintained rather than archived); and the 2ndQuadrant audit-trigger repository states that pull requests are not accepted and describes itself as “meant to be a demo more than a ready-to-run extension”. |
| `aha` | Aha! engineering, on removing a generic audit-trigger table that had grown to billions of rows and roughly half the database while over 90% of queries touched only the last 30 days. |
| `qldb` | Amazon QLDB reached end of support on 31 July 2025; ledger-style immutability is now generally implemented on general-purpose engines plus object storage with retention locks. |

## Privacy and compliance

| Key | Source |
|---|---|
| `gdpr7` | Regulation (EU) 2016/679, Article 7(1) — where processing is based on consent, the controller “shall be able to demonstrate” that the data subject consented; Article 7(3) — withdrawal shall be as easy as giving consent. |
| `gdpr17` | Regulation (EU) 2016/679, Articles 17 (erasure) and 5(1)(e) (storage limitation), read with Article 17(3) exemptions for legal obligations and legal claims. |
| `gdpr33` | Regulation (EU) 2016/679, Art. 33(1) — notify the supervisory authority “without undue delay and, where feasible, not later than 72 hours after having become aware of it”; Art. 34(1) — communicate to the data subject without undue delay where the breach is likely to result in a high risk to rights and freedoms. |
| `ndpa` | Nigeria Data Protection Act 2023 §40 — notify the Commission within 72 hours. The General Application and Implementation Directive 2025 is reported to require notification to affected data subjects immediately where the breach is likely to result in high risk (Art. 33). UNVERIFIED: the Commission’s document portal could not be reached during this research pass, so the directive’s date, article number and exact wording have not been confirmed against the primary text. Confirm with the NDPC before relying on it. |
| `kenya` | Kenya Data Protection Act 2019 §43(1)(a) — notify the Data Commissioner “without delay, within seventy-two hours of becoming aware of such breach”; the data subject where there is a real risk of harm. §50 gives the Cabinet Secretary a power to prescribe processing through a server or data centre located in Kenya on grounds of strategic state interest or protection of revenue; no general localisation mandate has been made under it, though sector-specific transfer restrictions exist (e.g. the Civil Registration Regulations 2020). |
| `popia` | South Africa, Protection of Personal Information Act 4 of 2013 — notification to the Regulator and to data subjects as soon as reasonably possible after discovery. |
| `hipaa` | HIPAA Security Rule, 45 CFR §164.312(b) and §164.316(b)(2)(i) — audit controls, and documentation retained for six years. |
| `hipaabreach` | HIPAA Breach Notification Rule, 45 CFR §§164.404–164.408 — individual notice without unreasonable delay and no later than 60 days. |
| `pcidss` | PCI DSS v4.0.1 — requirement 10.2.2 lists the fields every audit record must contain; 10.5.1 requires 12 months of audit history with at least the last 3 months immediately available. |
| `nist88` | NIST SP 800-88 Rev. 2 (final, 26 September 2025) — Cryptographic Erase is classified as a logical Purge technique: “a purge sanitization technique in which key sanitization is applied to one or more keys providing confidentiality protections.” Separately, no EDPB or ICO guidance was located that endorses key destruction alone as satisfying GDPR Article 17 erasure; the ICO frames the question as putting data “beyond use”. |

## Domain and modelling

| Key | Source |
|---|---|
| `fhir` | HL7 FHIR — PractitionerRole binds a practitioner to an organisation, location, specialty and period; Consent carries scope, category, actor and period; RelatedPerson models proxies. |
| `cfr395` | 49 CFR §395.22 — ELD accounts are anchored to the driver’s licence, and the licence number must not be used as the account identifier. |
| `silver` | Len Silverston, The Data Model Resource Book — the party/role pattern: a party is a person or organisation, and roles are separate, dated relationships rather than columns on the party. |
| `kimball` | Ralph Kimball, The Data Warehouse Toolkit — bridge tables and type-2 slowly changing dimensions for reconstructing a hierarchy as at a past date. |
| `edfi` | Ed-Fi and OneRoster data standards — employment and assignment are distinct dated associations; a person can be employed by one organisation and assigned to another. |
| `shopify` | Shopify POS role documentation — staff at a physical till authenticate with a PIN against a location-scoped role, and individual permissions can be set to allowed, denied, or requiring manager approval. |
| `stripeR` | Stripe dashboard user roles — narrowly scoped operational roles are separated (for example refund handling is distinct from dispute handling) rather than combined into one “support” role. |
