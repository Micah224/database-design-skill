# Question bank

All 113 questions, with the answer codes to record in `answers.json`. Questions with a *Shown when* condition appear only when earlier answers make them relevant; the `questions.js` script evaluates that for you — this file is the human-readable catalogue.

Every question also accepts `__other`: record the free text in the `other` map of the answers file. It is carried verbatim into the brief and flagged for a human decision.

## Contents

- Section A — Domain & risk (5 questions)
- Section B — Scale & data shape (10 questions)
- Section C — Identity (9 questions)
- Section D — Authentication (9 questions)
- Section E — User account features (7 questions)
- Section F — Organisation model (6 questions)
- Section G — Staff & roles (9 questions)
- Section H — Admin & super-admin (8 questions)
- Section I — Authorization model (6 questions)
- Section J — Privacy & compliance (8 questions)
- Section K — Audit & evidence (4 questions)
- Section L — Operations & stack (11 questions)
- Section X — Domain specifics (21 questions)

## Section A — Domain & risk

What the system is for, and what happens when it is wrong. Almost every later rule keys off these five answers.

### A1 — Which best describes what the system is for?

- Type: single-select, required
- Why it is asked: Pick the closest. This drives the domain-specific questions in section X and several regulatory rules.

| Code | Answer | Note |
|---|---|---|
| `fintech` | Financial services — banking, payments, lending, wallets | You hold, move or lend other people’s money. |
| `health` | Healthcare or clinical | Patient records, care delivery, diagnostics, telehealth. |
| `b2bsaas` | B2B SaaS sold to organisations | Your customers are companies whose employees are your users. |
| `commerce` | Commerce, marketplace or retail | Catalogue, orders, payments, fulfilment, possibly physical stores. |
| `logistics` | Logistics, field service or fleet | Drivers, technicians, warehouses, routes, devices in the field. |
| `edu` | Education | Schools, universities, training providers, LMS. |
| `gov` | Government or public sector | Citizen services, licensing, records, statutory duties. |
| `internal` | Internal enterprise tool | Used only by your own staff; no external customers. |
| `social` | Consumer social, content or community | User-generated content, feeds, messaging, moderation. |
| `devtool` | Developer or infrastructure tooling | APIs, CI, observability, data platforms. |
| `__other` | Other — specify | Free text in the `other` map |

### A2 — Who will hold accounts in the system?

- Type: multi-select, required
- Why it is asked: Select every population. Each one you add tends to add an identifier policy, a verification level and a lifecycle.

| Code | Answer | Note |
|---|---|---|
| `public` | Members of the general public | Self-registering consumers. |
| `custstaff` | Employees of your business customers | Someone else’s staff — the classic B2B case. |
| `ownstaff` | Your own employees | Internal staff using the same system. |
| `contract` | Contractors, temps or gig workers | Time-boxed, often high-churn. |
| `partner` | Partners, resellers, franchisees or agents | Third parties acting on customers’ behalf. |
| `minor` | People under 18 | Triggers parental consent and age-assurance rules. |
| `proxy` | People represented by someone else | Patients with carers, clients with agents, wards with guardians. |
| `machine` | Machines, services or integrations | API keys, service accounts, webhooks. |
| `anon` | Unauthenticated / anonymous visitors | Guest checkout, public read, pre-signup activity. |
| `__other` | Other — specify | Free text in the `other` map |

### A3 — Is the system multi-tenant?

- Type: single-select, required
- Why it is asked: “Tenant” means an isolated customer organisation whose data must never mix with another’s. Getting this wrong is the single most expensive schema mistake to reverse.

| Code | Answer | Note |
|---|---|---|
| `single` | No — one organisation, one dataset | Internal tools, single-company products. |
| `shared` | Yes — shared schema, tenant_id on every row | Cheapest to run, hardest to get isolation right. |
| `schema` | Yes — one schema (or database) per tenant | Strong isolation, painful past a few hundred tenants. |
| `hybrid` | Hybrid — shared by default, dedicated for large customers | Common end-state; design for it from day one if you expect it. |
| `unsure` | Not sure yet | Answer honestly — the recommendation changes. |
| `__other` | Other — specify | Free text in the `other` map |

### A4 — What is the worst realistic consequence of a wrong, lost or leaked record?

- Type: single-select, required
- Why it is asked: Answer for the worst single record, not the average one. This sets the assurance floor for the whole design.

| Code | Answer | Note |
|---|---|---|
| `money` | Money moves and cannot be recovered | Payments, transfers, payroll, settlement. |
| `safety` | Someone’s health, liberty or physical safety is at risk | Clinical decisions, safeguarding, lone-worker, dispatch. |
| `legal` | Regulatory penalty, licence loss or court exposure | Statutory records, licensed activity. |
| `reput` | Serious reputational or competitive damage | Confidential business data, embargoed information. |
| `incon` | Inconvenience, recoverable within a day | Preferences, drafts, non-critical content. |
| `__other` | Other — specify | Free text in the `other` map |

### A5 — Does the system do any of these regulated things?

- Type: multi-select, required
- Why it is asked: Select all that apply, including “none”. Each of these pulls in a specific, named obligation — not a general “be careful”.

| Code | Answer | Note |
|---|---|---|
| `funds` | Holds or moves customer funds | E-money, custody, settlement, escrow. |
| `card` | Touches raw payment-card numbers (PAN) | Only if the PAN enters your systems. Hosted fields / tokenisation means no. |
| `phi` | Stores health or medical information |  |
| `child` | Knowingly collects data from children |  |
| `bio` | Processes biometrics (face, fingerprint, voice) | Special-category data in most regimes; some US states require separate consent. |
| `credit` | Makes automated credit, insurance or eligibility decisions | Triggers automated-decision and explainability duties. |
| `gov` | Maintains official or public records | Statutory retention schedules, disclosure regimes. |
| `crypto` | Deals in crypto-assets or virtual currency |  |
| `none` | None of the above |  |
| `__other` | Other — specify | Free text in the `other` map |

## Section B — Scale & data shape

Volume, shape and access pattern. This section picks the engine; nothing else does.

### B1 — How many rows will your largest single table hold 24 months after launch?

- Type: single-select, required
- Why it is asked: Estimate the busiest table (usually events, transactions, messages or line items), not the total database. Deliberately over-estimate rather than under.

| Code | Answer | Note |
|---|---|---|
| `tiny` | Under 1 million |  |
| `small` | 1 – 50 million |  |
| `mid` | 50 – 500 million |  |
| `large` | 500 million – 5 billion |  |
| `huge` | Over 5 billion |  |
| `unk` | Genuinely unknown | Fine. It will be treated as “small” with a re-check trigger. |
| `__other` | Other — specify | Free text in the `other` map |

### B2 — What is the read-to-write ratio on the busiest path?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `readheavy` | Overwhelmingly reads (95%+) | Catalogues, content, dashboards. |
| `balanced` | Mixed — roughly 70:30 to 50:50 |  |
| `writeheavy` | Write-heavy — ingest dominates | Telemetry, events, tracking, IoT. |
| `bursty` | Quiet, punctuated by extreme bursts | Ticket sales, results days, paydays, flash sales. |
| `__other` | Other — specify | Free text in the `other` map |

### B3 — Peak concurrent active users or connections at the busiest minute?

- Type: single-select, required
- Why it is asked: Concurrent, not registered. If you are unsure, take your expected daily actives and divide by 20.

| Code | Answer | Note |
|---|---|---|
| `p1` | Under 100 |  |
| `p2` | 100 – 2,000 |  |
| `p3` | 2,000 – 20,000 |  |
| `p4` | 20,000 – 200,000 |  |
| `p5` | Over 200,000 |  |
| `__other` | Other — specify | Free text in the `other` map |

### B4 — Does the dominant data have a time axis — is it a stream of dated events?

- Type: single-select, required
- Why it is asked: “Time-series” means rows are written in time order, queried by time range, and rarely updated after insert.

| Code | Answer | Note |
|---|---|---|
| `dominant` | Yes — the main table is an append-only event or transaction log |  |
| `secondary` | Partly — entities plus a large event/audit stream beside them |  |
| `no` | No — mostly mutable entities |  |
| `__other` | Other — specify | Free text in the `other` map |

### B5 — How variable is the shape of your records?

- Type: single-select, required
- Why it is asked: This is the honest test for “do I need a document store”, and it is answered by variability, not by preference.

| Code | Answer | Note |
|---|---|---|
| `fixed` | Fixed and knowable — you can draw the columns today |  |
| `mostly` | Mostly fixed, plus a handful of optional or customer-specific fields | The overwhelmingly common case. |
| `percust` | Each customer defines their own fields at runtime | Form builders, CRM-style custom objects, EAV pressure. |
| `poly` | Genuinely polymorphic documents with no stable core | Content ingestion, scraped data, heterogeneous payloads. |
| `__other` | Other — specify | Free text in the `other` map |

### B6 — Where are your users, physically?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `one` | One country |  |
| `region` | One region (e.g. EU, West Africa, US) |  |
| `multi` | Several regions, but latency is not critical |  |
| `global` | Global, and cross-region latency is a product problem |  |
| `__other` | Other — specify | Free text in the `other` map |

### B7 — What kind of search do users need?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `none` | None, or exact lookup by id |  |
| `prefix` | Prefix / substring filtering on a few fields |  |
| `fts` | Ranked full-text search over documents or listings |  |
| `rich` | Typo tolerance, faceting, synonyms or relevance tuning |  |
| `vector` | Semantic / vector similarity search | Embeddings, RAG, recommendations. |
| `__other` | Other — specify | Free text in the `other` map |

### B8 — What analytics do you need over this data?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `none` | None beyond a few counts |  |
| `light` | Operational dashboards over recent data | Under ~10M rows scanned per query. |
| `heavy` | Heavy aggregation, cohorts, funnels across the full history |  |
| `wh` | A separate warehouse / lakehouse is already planned |  |
| `__other` | Other — specify | Free text in the `other` map |

### B9 — What consistency does the core write path require?

- Type: single-select, required
- Why it is asked: Be precise. “Eventual is fine” is a correct answer for a feed and a catastrophic one for a balance.

| Code | Answer | Note |
|---|---|---|
| `strict` | Strict — no double-spend, no lost update, ever | Balances, inventory, seat booking, limits. |
| `rc` | Read-committed with explicit locking where it matters | The normal transactional default. |
| `eventual` | Eventual consistency is acceptable | Feeds, counters, search indexes, analytics. |
| `unsure` | Not sure |  |
| `__other` | Other — specify | Free text in the `other` map |

### B10 — Do clients need to work offline and sync later?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No — always online |  |
| `degraded` | Read-only or degraded mode when offline |  |
| `full` | Full offline writes with conflict resolution on reconnect | Field apps, POS, clinical devices, maritime/rural. |
| `__other` | Other — specify | Free text in the `other` map |

## Section C — Identity

How a human becomes a row. Identifiers, verification, and whether one human can be several accounts.

### C1 — What will end users type into the “username” field?

- Type: multi-select, required
- Why it is asked: The login handle is a schema decision with a uniqueness constraint attached, and it is very hard to change later. Pick every handle you will accept.

| Code | Answer | Note |
|---|---|---|
| `email` | Email address |  |
| `phone` | Phone number (E.164) |  |
| `user` | A chosen username |  |
| `natid` | A national ID, licence or registration number | Never make this the login handle — see the warning if you pick it. |
| `staffno` | An employee, student or member number |  |
| `ssoonly` | Nothing — they arrive via SSO or a social provider only |  |
| `__other` | Other — specify | Free text in the `other` map |

### C2 — What is the login policy for staff and internal users?

- Type: single-select, required
- Shown when: `anyOf('A2','ownstaff','custstaff','contract','partner')`
- Why it is asked: The common hybrid is: end users use anything, staff must use a corporate identity. Say which you mean.

| Code | Answer | Note |
|---|---|---|
| `ssoforced` | Corporate SSO only — no local password exists for staff | Strongest, and the only model where offboarding is truly one action. |
| `domain` | Company email domain only, with MFA, but local accounts | Domain allow-list enforced at invite and at login. |
| `invite` | Any email address, but admin-invited only | Common for franchisees, partners, small merchants. |
| `same` | Same as end users | Acceptable only if staff privileges are trivial. |
| `mixed` | Depends on privilege level — high privilege forces SSO | Explicitly hybrid. |
| `__other` | Other — specify | Free text in the `other` map |

### C3 — Do your business customers need to bring their own identity provider?

- Type: single-select, required
- Shown when: `anyOf('A2','custstaff','partner')||has('A1','b2bsaas')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `oidc` | Yes — OIDC (Entra ID, Google Workspace, Okta) |  |
| `saml` | Yes — SAML 2.0 | Still mandatory for many large enterprises. |
| `both` | Both, plus SCIM provisioning | The realistic enterprise-tier requirement. |
| `later` | Not at launch, but certainly later |  |
| `__other` | Other — specify | Free text in the `other` map |

### C4 — How strongly must you prove that a user is who they claim to be?

- Type: single-select, required
- Why it is asked: This is identity proofing (IAL), which NIST SP 800-63-4 makes independent of how strongly they authenticate later (AAL). Do not conflate the two.

| Code | Answer | Note |
|---|---|---|
| `ial0` | Not at all — pseudonymous accounts are fine | Forums, content, anonymous reporting. |
| `ial1` | Possession of an email or phone is enough | Most consumer products. |
| `ial2` | Remote verification against a government document | KYC, regulated onboarding, high-value accounts. |
| `ial3` | In-person or supervised remote proofing | Rare: clinicians, officials, high-value custody. |
| `derived` | Inherited — the employer or partner already proofed them | You trust the IdP assertion. |
| `__other` | Other — specify | Free text in the `other` map |

### C5 — How do accounts come into existence?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `self` | Self-service registration, open to anyone |  |
| `invite` | Invitation only, issued by an admin |  |
| `both` | Both — public signup for customers, invitation for staff |  |
| `prov` | Provisioned automatically from an upstream system | HR system, SIS, SCIM, government register. |
| `approve` | Self-service application, then manual approval | Marketplaces, provider networks, B2B accounts. |
| `__other` | Other — specify | Free text in the `other` map |

### C6 — Can one human legitimately hold more than one account?

- Type: single-select, required
- Why it is asked: Answer for the real world, not the ideal. A shop owner who is also a customer will find a way.

| Code | Answer | Note |
|---|---|---|
| `one` | No — one human, one account, enforced |  |
| `roles` | One account that can hold several roles at once | Preferred: one principal, many role assignments. |
| `pertenant` | One account per tenant/organisation they belong to |  |
| `sep` | Deliberately separate accounts for separate capacities | Personal vs. admin — a recognised privileged-access pattern. |
| `nolimit` | No constraint — duplicates are tolerated |  |
| `__other` | Other — specify | Free text in the `other` map |

### C7 — Does anyone ever act on another person’s behalf?

- Type: multi-select, required
- Why it is asked: Every “yes” here is a relationship table with a validity period and an evidence trail — not a flag on the user row.

| Code | Answer | Note |
|---|---|---|
| `none` | No |  |
| `parent` | A parent or guardian for a child |  |
| `carer` | A carer, family member or next of kin |  |
| `poa` | A legally appointed representative (power of attorney, deputy) |  |
| `agent` | A professional agent — accountant, broker, lawyer, adviser |  |
| `staffimp` | Your support staff, acting as the user to help them |  |
| `delegate` | A colleague covering for someone who is away |  |
| `__other` | Other — specify | Free text in the `other` map |

### C8 — Which personal attributes will you actually store?

- Type: multi-select, required
- Why it is asked: Select only what you have a concrete, present use for. Every extra attribute is a retention obligation, a subject-access obligation and a breach-notification obligation.

| Code | Answer | Note |
|---|---|---|
| `nameonly` | Name and contact only |  |
| `dob` | Date of birth |  |
| `gender` | Gender or sex |  |
| `addr` | Postal address |  |
| `nat` | Nationality or immigration status | Special category in the EU/UK when it reveals race or ethnicity. |
| `govid` | Government ID number |  |
| `employ` | Employer or job details |  |
| `fin` | Income, financial or credit data |  |
| `health` | Health data |  |
| `bio` | Biometric templates |  |
| `loc` | Precise location history |  |
| `ethnic` | Race, ethnicity, religion, politics, union membership or sexual orientation | Special category — needs an Article 9 condition, not just consent. |
| `__other` | Other — specify | Free text in the `other` map |

### C9 — Do you need to know a user’s age or age band?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `self` | Self-declared age is sufficient |  |
| `band` | Verified age band only (over/under a threshold) | Privacy-preserving: store the band, not the birth date. |
| `exact` | Verified exact date of birth | Only if a rule genuinely depends on the exact date. |
| `__other` | Other — specify | Free text in the `other` map |

## Section D — Authentication

Assurance level, authenticators and recovery. NIST SP 800-63-4 (final, 31 Jul 2025) is the reference throughout.

### D1 — What authentication assurance do ordinary end users need?

- Type: single-select, required
- Why it is asked: AAL is defined in NIST SP 800-63B-4. AAL1 = one factor. AAL2 = two distinct factors, phishing resistance recommended. AAL3 = hardware-bound, verifier-impersonation-resistant, mandatory.

| Code | Answer | Note |
|---|---|---|
| `aal1` | AAL1 — a single factor is proportionate | Low-value content, read-only accounts. |
| `aal2` | AAL2 — multi-factor required | Anything holding money, personal data or business records. |
| `aal2p` | AAL2 with phishing resistance required | Passkeys or security keys only; no OTP fallback. |
| `aal3` | AAL3 — hardware-bound authenticator required | Rare for end users. Synced passkeys cannot reach AAL3. |
| `__other` | Other — specify | Free text in the `other` map |

### D2 — What assurance do staff, admins and super-admins need?

- Type: single-select, required
- Why it is asked: Set this independently of D1. Almost every real breach of an admin console was an AAL2-with-OTP account, not an AAL1 one.

| Code | Answer | Note |
|---|---|---|
| `same` | Same as end users |  |
| `aal2` | AAL2 — multi-factor |  |
| `aal2p` | AAL2, phishing-resistant only | The current baseline recommendation for any administrative access. |
| `aal3` | AAL3 — hardware-bound, for the highest privileges | Device-bound passkeys, PIV/CAC or FIDO2 security keys. |
| `__other` | Other — specify | Free text in the `other` map |

### D3 — Which authenticators will you support?

- Type: multi-select, required
- Why it is asked: Select everything you will actually ship. The schema differs materially per type; a single “mfa_secret” column is a design error.

| Code | Answer | Note |
|---|---|---|
| `pw` | Password |  |
| `pksync` | Passkey, synced across the user’s devices | iCloud Keychain, Google Password Manager, 1Password. |
| `pkbound` | Device-bound passkey or FIDO2 security key | YubiKey, platform authenticator with no export. |
| `totp` | TOTP authenticator app |  |
| `push` | Push approval with number matching |  |
| `sms` | SMS or voice one-time code |  |
| `emailotp` | Email one-time code or magic link |  |
| `social` | Google / Apple / Microsoft sign-in |  |
| `smartcard` | Smart card, PIV/CAC or client certificate |  |
| `backup` | One-time backup codes |  |
| `__other` | Other — specify | Free text in the `other` map |

### D4 — What happens when a user loses their only authenticator?

- Type: single-select, required
- Why it is asked: Account recovery is the real authentication strength of your system. An AAL2 login with an AAL0 recovery path is an AAL0 system.

| Code | Answer | Note |
|---|---|---|
| `emaillink` | Emailed reset link |  |
| `sms` | SMS code to the registered number |  |
| `codes` | Pre-issued backup codes |  |
| `second` | A second registered authenticator must be used | Enrol two at registration; strongest and cheapest. |
| `helpdesk` | Support desk re-verifies identity | Then re-proofing must be at least as strong as original proofing. |
| `admin` | An administrator resets it | Needs its own approval and audit path — it is a privileged action. |
| `none` | No recovery — the account is lost | Legitimate for some custody and high-security designs. |
| `__other` | Other — specify | Free text in the `other` map |

### D5 — How long should an ordinary user stay signed in?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `short` | Minutes to an hour of inactivity |  |
| `day` | A working day |  |
| `weeks` | Weeks — “remember me” by default |  |
| `forever` | Indefinitely, until they sign out |  |
| `__other` | Other — specify | Free text in the `other` map |

### D6 — How long should a privileged administrative session last?

- Type: single-select, required
- Why it is asked: The current guidance sets an overall reauthentication timeout of no more than 30 days at AAL1 and 24 hours at AAL2 (both SHOULD), with a 1-hour inactivity timeout at AAL2; at AAL3 the overall timeout SHALL be no more than 12 hours with a 15-minute inactivity timeout. Activity resets the inactivity clock but never the overall one.

| Code | Answer | Note |
|---|---|---|
| `15m` | 15 minutes idle, 12 hours absolute | AAL3-consistent. |
| `30m` | Up to 1 hour idle, 24 hours absolute | AAL2-consistent. |
| `day` | A working day |  |
| `same` | Same as ordinary users | A finding in most audits. |
| `__other` | Other — specify | Free text in the `other` map |

### D7 — Do you need to recognise and manage devices?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `known` | Remember known devices to reduce MFA friction |  |
| `list` | Users can list and revoke their own devices and sessions |  |
| `managed` | Only enrolled or corporate-managed devices may connect | Device posture becomes an authorization input. |
| `__other` | Other — specify | Free text in the `other` map |

### D8 — Which actions should force a fresh, stronger authentication?

- Type: multi-select, required
- Why it is asked: Step-up is a session property, not a page. If you select any of these you need an assurance level and a satisfied-at timestamp on the session row.

| Code | Answer | Note |
|---|---|---|
| `none` | None |  |
| `money` | Moving money or changing payout details |  |
| `pii` | Viewing or exporting bulk personal data |  |
| `perm` | Granting or changing permissions |  |
| `contact` | Changing email, phone or password |  |
| `delete` | Deleting an account or destroying data |  |
| `imperson` | Impersonating another user |  |
| `config` | Changing security or tenant-wide configuration |  |
| `__other` | Other — specify | Free text in the `other` map |

### D9 — How much automated abuse do you expect against sign-up and sign-in?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `low` | Low — closed audience, invite-only |  |
| `med` | Normal public-internet background noise |  |
| `high` | High — credential stuffing, bulk fake accounts, promo abuse | Consumer fintech, marketplaces, anything with free credit. |
| `__other` | Other — specify | Free text in the `other` map |

## Section E — User account features

What an account must be able to do on day one. Several of these are legal requirements, not product choices.

### E1 — Which account self-service capabilities must exist at launch?

- Type: multi-select, required
- Why it is asked: Some of these are not optional if a data-protection regime applies to you. The recommendation will tell you which ones your regime forces.

| Code | Answer | Note |
|---|---|---|
| `chgemail` | Change email address | With verification of the new address before it becomes the login handle. |
| `chgphone` | Change phone number |  |
| `chgpw` | Change password |  |
| `mfa` | Enrol, list and remove authenticators |  |
| `sessions` | See active sessions and sign out elsewhere |  |
| `export` | Download a copy of their data |  |
| `delete` | Delete or close the account |  |
| `consent` | A consent / preference centre with withdrawal |  |
| `notif` | Notification channel preferences |  |
| `activity` | View their own access and activity history |  |
| `tokens` | Create and revoke API tokens |  |
| `lang` | Language, locale, timezone and accessibility settings |  |
| `__other` | Other — specify | Free text in the `other` map |

### E2 — How will the system contact users?

- Type: multi-select, required

| Code | Answer | Note |
|---|---|---|
| `email` | Email |  |
| `sms` | SMS |  |
| `push` | Mobile push |  |
| `inapp` | In-app inbox |  |
| `whatsapp` | WhatsApp or similar messaging channel |  |
| `post` | Physical post |  |
| `webhook` | Webhooks to customer systems |  |
| `__other` | Other — specify | Free text in the `other` map |

### E3 — Do users have a profile that other users can see?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No — accounts are private |  |
| `org` | Visible within their own organisation only |  |
| `opt` | Optional public profile |  |
| `public` | Public by default | Then a display name must be separable from the legal name. |
| `__other` | Other — specify | Free text in the `other` map |

### E4 — Do you store payment instruments?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No payments at all |  |
| `token` | Tokens only — the processor holds the card | Keeps you out of most of PCI DSS scope. |
| `bank` | Bank account or payout details |  |
| `pan` | Card numbers in our own systems | Full PCI DSS scope. Expect this to dominate the design. |
| `__other` | Other — specify | Free text in the `other` map |

### E5 — Do users belong to groups that share access to things?

- Type: single-select, required
- Why it is asked: Teams, households, families, practices, classes, sites. If yes, membership is a first-class table with a role and a period, not an array column.

| Code | Answer | Note |
|---|---|---|
| `no` | No — every account is independent |  |
| `flat` | Yes — a flat group or team |  |
| `nested` | Yes — nested groups, folders or spaces |  |
| `multi` | Yes, and a user can be in many groups with different rights in each |  |
| `__other` | Other — specify | Free text in the `other` map |

### E6 — Do you need plans, entitlements or usage quotas?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `plan` | Simple plan tiers |  |
| `seat` | Per-seat licensing that must be counted and enforced |  |
| `meter` | Metered usage that drives billing | The metering table is usually your largest table — plan for it in section B. |
| `flags` | Per-customer feature flags and limits |  |
| `__other` | Other — specify | Free text in the `other` map |

### E7 — Do users create content that someone must review or moderate?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `react` | Yes — reported content is reviewed after publication |  |
| `pre` | Yes — content is reviewed before publication |  |
| `both` | Both, with automated classification in front |  |
| `__other` | Other — specify | Free text in the `other` map |

## Section F — Organisation model

Departments, branches, regions, legal entities — and whether you must be able to reconstruct them as at a past date.

### F1 — What internal structure exists beyond “admin and user”?

- Type: multi-select, required
- Why it is asked: Select every axis you must model. Two or more selections almost always means two or more independent hierarchies, not one tree with mixed node types.

| Code | Answer | Note |
|---|---|---|
| `none` | None — a flat list of people |  |
| `dept` | Departments or functions |  |
| `branch` | Branches, stores, sites or clinics |  |
| `region` | Regions or territories |  |
| `legal` | Legal entities or subsidiaries |  |
| `cost` | Cost centres or budget units |  |
| `team` | Project teams or squads |  |
| `franch` | Franchises, partners or independent operators |  |
| `ward` | Wards, units or service lines |  |
| `__other` | Other — specify | Free text in the `other` map |

### F2 — How deep does that structure go, and is there more than one of it?

- Type: single-select, required
- Shown when: `!has('F1','none')`

| Code | Answer | Note |
|---|---|---|
| `flat` | Flat — one level |  |
| `fixed` | Fixed depth, e.g. region → branch → team |  |
| `arb` | Arbitrary depth, and it changes |  |
| `multi` | Several overlapping hierarchies at once | e.g. legal ownership vs. operational reporting vs. geography. They must be separate trees. |
| `__other` | Other — specify | Free text in the `other` map |

### F3 — Do you need to reconstruct the structure as it stood on a past date?

- Type: single-select, required
- Shown when: `!has('F1','none')`
- Why it is asked: “Who managed this branch in March, and who did they report to?” If you will ever be asked that, current-state-only tables cannot answer it and no amount of later work will recover the history.

| Code | Answer | Note |
|---|---|---|
| `current` | No — current state only |  |
| `hist` | Yes — historical reconstruction is required |  |
| `future` | Yes, and changes must also be scheduled in advance | Effective-dated transfers, term starts, planned reorganisations. |
| `__other` | Other — specify | Free text in the `other` map |

### F4 — Can one person be attached to more than one unit at the same time?

- Type: single-select, required
- Shown when: `!has('F1','none')`

| Code | Answer | Note |
|---|---|---|
| `no` | No — exactly one |  |
| `primary` | One primary, plus secondary attachments | Needs a constraint that enforces exactly one primary at any instant. |
| `many` | Freely many, with no primary |  |
| `cover` | Yes, including temporary cover with an end date |  |
| `__other` | Other — specify | Free text in the `other` map |

### F5 — Do units cross national or legal-entity boundaries?

- Type: single-select, required
- Shown when: `!has('F1','none')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `legal` | Yes — several legal entities, one country |  |
| `intl` | Yes — several countries | Then unit nodes carry a jurisdiction, and jurisdiction becomes an authorization input. |
| `__other` | Other — specify | Free text in the `other` map |

### F6 — Do your customer organisations have their own internal structure that you must model?

- Type: single-select, required
- Shown when: `anyOf('A3','shared','schema','hybrid')`

| Code | Answer | Note |
|---|---|---|
| `no` | No — a tenant is a flat bag of users |  |
| `flat` | Teams or workspaces inside a tenant |  |
| `deep` | A full hierarchy inside each tenant, defined by them |  |
| `group` | Customers themselves form groups — parent companies with subsidiaries | Tenants of tenants: decide now, it is very expensive later. |
| `__other` | Other — specify | Free text in the `other` map |

## Section G — Staff & roles

How a job function becomes a grant, who scopes it, and which duties must never meet in one person.

### G1 — How many genuinely distinct staff job functions will the system need to distinguish?

- Type: single-select, required
- Why it is asked: Count functions that need different permissions, not job titles.

| Code | Answer | Note |
|---|---|---|
| `r1` | 1 – 3 |  |
| `r2` | 4 – 10 |  |
| `r3` | 11 – 30 |  |
| `r4` | More than 30 |  |
| `r5` | Unknown — each customer will define their own | Then roles are data, not code, from day one. |
| `__other` | Other — specify | Free text in the `other` map |

### G2 — How does a person actually get a role?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `manual` | An administrator assigns it by hand |  |
| `derived` | It is derived from HR attributes — job code, department, grade | The maintainable model at scale, but it needs an authoritative source. |
| `request` | The person requests it and someone approves |  |
| `idp` | It arrives from the identity provider or HR system | SCIM groups or OIDC claims; then your app must not be the source of truth. |
| `mixed` | A derived baseline plus manual exceptions | The realistic answer in most organisations. |
| `__other` | Other — specify | Free text in the `other` map |

### G3 — Are staff permissions scoped to the part of the organisation they work in?

- Type: single-select, required
- Why it is asked: This is the difference between “can approve refunds” and “can approve refunds for the Lagos branch”. It changes the shape of every permission check.

| Code | Answer | Note |
|---|---|---|
| `global` | No — a permission applies everywhere |  |
| `own` | Yes — to their own unit only |  |
| `inherit` | Yes — to their unit and everything beneath it | A regional manager sees all branches in the region. |
| `explicit` | Yes — to an explicit list of units, not necessarily a subtree |  |
| `object` | Down to individual records shared with them |  |
| `__other` | Other — specify | Free text in the `other` map |

### G4 — Do staff ever need temporarily elevated rights?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `jit` | Yes — request, approve, time-boxed, auto-expiring | “Eligible” is not the same as “assigned”: model both. |
| `cover` | Yes — for holiday or absence cover |  |
| `emerg` | Yes — emergency break-glass access | Must be a role someone assumes, never a boolean on a user row. |
| `__other` | Other — specify | Free text in the `other` map |

### G5 — Which duties must never be held by the same person at the same time?

- Type: multi-select, required
- Why it is asked: Separation of duties is a database constraint you can test for, not a policy document. Select every pair that matters.

| Code | Answer | Note |
|---|---|---|
| `none` | None |  |
| `maker` | Whoever initiates a payment must not approve it |  |
| `iam` | Whoever grants access must not be the person who reviews the logs |  |
| `refund` | Refunds and dispute handling are different people |  |
| `publish` | Whoever writes content must not approve its publication |  |
| `vendor` | Whoever creates a supplier must not pay one |  |
| `stock` | Whoever adjusts stock must not count it |  |
| `clinical` | Whoever orders a treatment must not verify it |  |
| `grade` | Whoever teaches must not moderate their own grades |  |
| `__other` | Other — specify | Free text in the `other` map |

### G6 — Is access tied to a shift, roster or opening hours?

- Type: single-select, required
- Shown when: `anyOf('A2','ownstaff','contract')||anyOf('F1','branch','ward')`

| Code | Answer | Note |
|---|---|---|
| `no` | No — access is continuous |  |
| `soft` | Out-of-hours access is logged and reviewed, not blocked |  |
| `hard` | Access is denied outside the rostered window |  |
| `__other` | Other — specify | Free text in the `other` map |

### G7 — Do staff share a physical terminal, till or workstation?

- Type: single-select, required
- Shown when: `anyOf('F1','branch','ward')||anyOf('A1','commerce','health','logistics')`
- Why it is asked: Shared devices are where accountability quietly dies. If several people use one screen, the device session and the human session are different objects.

| Code | Answer | Note |
|---|---|---|
| `no` | No — one person, one device |  |
| `pin` | Yes — a fast PIN or badge switches the acting user | Device is authenticated once; the human is authenticated per action. |
| `full` | Yes — full sign-out and sign-in between users |  |
| `__other` | Other — specify | Free text in the `other` map |

### G8 — Do you have field or mobile staff with unreliable connectivity?

- Type: single-select, required
- Shown when: `anyOf('A1','logistics','health','commerce','gov')||has('B10','full')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `cached` | Yes — permissions must be cached and work offline | Then cached decisions need a version stamp and a bounded staleness. |
| `queue` | Yes — they also capture work offline and sync later |  |
| `__other` | Other — specify | Free text in the `other` map |

### G9 — Do contractor or partner accounts need a hard expiry?

- Type: single-select, required
- Shown when: `anyOf('A2','contract','partner')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `date` | Yes — a mandatory end date, enforced at grant time |  |
| `sponsor` | Yes — plus a named internal sponsor who must re-attest periodically |  |
| `__other` | Other — specify | Free text in the `other` map |

## Section H — Admin & super-admin

Custom roles, grant ceilings, impersonation, break-glass and recertification.

### H1 — Can an administrator create new roles, or only use the ones you ship?

- Type: single-select, required
- Why it is asked: This is the question the whole permission schema hangs on. If roles are data, permissions must be a registry with stable identifiers; if roles are code, they can be an enum.

| Code | Answer | Note |
|---|---|---|
| `fixed` | No — a fixed set of roles defined by us | Simplest. Viable only while G1 stays small and customers stay similar. |
| `catalog` | Yes — assembled freely from a catalogue of permissions | Maximum flexibility, maximum support burden. |
| `delta` | Yes — but only as “a shipped role, plus or minus specific permissions” | The pattern used by most mature B2B products: bounded, explainable, upgradeable. |
| `pertenant` | Yes, and each customer’s custom roles are private to them | Roles need a tenant_id that is NULL for system roles. |
| `later` | Not at launch, but certainly later | Then build the registry now and the UI later. |
| `__other` | Other — specify | Free text in the `other` map |

### H2 — Who is allowed to grant what?

- Type: single-select, required
- Why it is asked: Without a ceiling, any admin who can edit roles is a super-admin, whatever the UI implies.

| Code | Answer | Note |
|---|---|---|
| `any` | Any administrator can grant any role |  |
| `subset` | An admin can only grant permissions they hold themselves | No privilege escalation by construction. |
| `explicit` | Each role declares which roles it may grant | Explicit grantable sets; the clearest to audit. |
| `approve` | Granting privileged roles needs a second approver |  |
| `scoped` | An admin can only grant within their own part of the organisation |  |
| `__other` | Other — specify | Free text in the `other` map |

### H3 — How should the highest level of access work?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `person` | A named super-admin account that always has everything |  |
| `break` | A break-glass role that must be deliberately assumed, time-boxed and alarmed | The recommended pattern: no standing total power. |
| `dual` | Two people must act together for the highest operations |  |
| `none` | No single account can do everything, by design |  |
| `__other` | Other — specify | Free text in the `other` map |

### H4 — Does support staff need to see or use the product as a specific user?

- Type: single-select, required
- Why it is asked: Impersonation and delegation are different things and must not share a code path. Impersonation hides the actor; delegation preserves both identities.

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `readonly` | Read-only “view as” — no actions can be taken |  |
| `consent` | Full impersonation, but only with the user’s explicit consent |  |
| `logged` | Full impersonation with mandatory reason, notification and dual logging |  |
| `unrestricted` | Full impersonation, no ceremony | Expect this to become an audit finding. |
| `__other` | Other — specify | Free text in the `other` map |

### H5 — Which administrative actions need a second person to approve them?

- Type: multi-select, required

| Code | Answer | Note |
|---|---|---|
| `none` | None |  |
| `grant` | Granting a privileged role |  |
| `money` | Payments, refunds or payout changes above a threshold |  |
| `export` | Bulk export of personal data |  |
| `delete` | Deleting accounts or purging data |  |
| `config` | Changing security configuration |  |
| `price` | Changing prices, limits or credit |  |
| `break` | Invoking break-glass access |  |
| `__other` | Other — specify | Free text in the `other` map |

### H6 — Do you need periodic access reviews?

- Type: single-select, required
- Why it is asked: Recertification is a scheduled, evidenced campaign — a snapshot of who had what, and a signed decision per line. It cannot be reconstructed from live tables.

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `informal` | Informally, when someone remembers |  |
| `periodic` | Yes — a scheduled campaign with recorded attestations |  |
| `evented` | Yes — plus triggered reviews on transfer or role change |  |
| `__other` | Other — specify | Free text in the `other` map |

### H7 — What must administrators be able to see?

- Type: multi-select, required

| Code | Answer | Note |
|---|---|---|
| `users` | User and account lists with lifecycle state |  |
| `access` | Who currently holds which permission, and why |  |
| `activity` | Activity and audit search |  |
| `usage` | Product usage and adoption metrics |  |
| `finance` | Revenue, billing and settlement figures |  |
| `ops` | Operational health — queues, failures, latency |  |
| `risk` | Fraud, abuse or risk signals |  |
| `compliance` | Compliance status — consents, requests, retention, reviews |  |
| `__other` | Other — specify | Free text in the `other` map |

### H8 — Do your customers administer their own users?

- Type: single-select, required
- Shown when: `anyOf('A3','shared','schema','hybrid')`

| Code | Answer | Note |
|---|---|---|
| `no` | No — we do all administration |  |
| `yes` | Yes — each customer has their own administrators |  |
| `partial` | Customers manage users; we retain platform-level controls |  |
| `partner` | A partner or reseller administers on the customer’s behalf | Three-party authorization: partner → customer → user. |
| `__other` | Other — specify | Free text in the `other` map |

## Section I — Authorization model

What a permission check actually depends on, and where the decision should be made.

### I1 — What does a permission decision actually depend on?

- Type: multi-select, required
- Why it is asked: Select everything a real check must consider. The number of different kinds of input here — not the number of roles — determines which model you need.

| Code | Answer | Note |
|---|---|---|
| `role` | The person’s role alone |  |
| `unit` | Their role plus the organisational unit of the record |  |
| `rel` | Their relationship to the specific record | Owner, member, invited, assigned, shared-with. |
| `attr` | Attributes of the request — amount, time, location, channel, device |  |
| `state` | The state of the record — draft vs. published, open vs. closed |  |
| `consent` | Whether the data subject consented to this access |  |
| `clear` | A clearance or sensitivity label |  |
| `assign` | Whether the record is currently assigned to them | Care teams, case work, tickets. |
| `__other` | Other — specify | Free text in the `other` map |

### I2 — Do you need to answer “who can access this record?” and “what can this person access?” as fast queries?

- Type: single-select, required
- Why it is asked: Forward checks are easy in any model. Reverse and enumeration queries are where attribute-only designs become expensive.

| Code | Answer | Note |
|---|---|---|
| `no` | No — only “may this person do this?” |  |
| `list` | Yes — list what a person can see, for their home screen |  |
| `both` | Yes — both directions, on demand |  |
| `audit` | Yes, and as at a past date, for auditors |  |
| `__other` | Other — specify | Free text in the `other` map |

### I3 — How do users share things with each other?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `none` | They do not |  |
| `named` | With specific named people |  |
| `link` | By link, possibly to people without accounts |  |
| `orgwide` | With everyone in their organisation |  |
| `nested` | Through nested folders or spaces that inherit access | Relationship-based access control territory. |
| `__other` | Other — specify | Free text in the `other` map |

### I4 — Do you need explicit denies or exceptions?

- Type: single-select, required
- Why it is asked: The RBAC standard has no negative permissions. If you need them, you are choosing a model where deny always wins and ordering never matters.

| Code | Answer | Note |
|---|---|---|
| `no` | No — everything is additive |  |
| `block` | Yes — block a specific person from a specific record |  |
| `legal` | Yes — legal or ethical walls between groups | Conflict-of-interest separation, patient/staff overlap, deal teams. |
| `temp` | Yes — temporary suspension without removing the role |  |
| `__other` | Other — specify | Free text in the `other` map |

### I5 — What is the latency budget for a single permission check?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `sub1` | Under 1 ms — it is inside a tight loop or a row filter |  |
| `ms10` | Under 10 ms |  |
| `ms50` | Under 50 ms — a normal request |  |
| `lax` | 100 ms or more is fine |  |
| `__other` | Other — specify | Free text in the `other` map |

### I6 — Where should the authorization decision be made?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `db` | In the database, as a row filter |  |
| `app` | In application code |  |
| `svc` | In a dedicated policy service |  |
| `both` | In the application, with the database as a backstop | Defence in depth: the usual right answer when the data is sensitive. |
| `unsure` | Not sure |  |
| `__other` | Other — specify | Free text in the `other` map |

## Section J — Privacy & compliance

Regimes, consent evidence, erasure, residency and retention. These become tables, not policies.

### J1 — Which data-protection or security regimes apply to you?

- Type: multi-select, required
- Why it is asked: Select every regime that could apply to any user population you serve, not only your home jurisdiction.

| Code | Answer | Note |
|---|---|---|
| `gdpr` | EU GDPR and/or UK GDPR |  |
| `ndpa` | Nigeria — NDPA 2023 and GAID 2025 |  |
| `kenya` | Kenya — Data Protection Act 2019 |  |
| `popia` | South Africa — POPIA |  |
| `afother` | Another African regime (Ghana, Rwanda, Egypt, Cameroon, …) |  |
| `us` | US state privacy law (CCPA/CPRA and successors) |  |
| `hipaa` | HIPAA |  |
| `pci` | PCI DSS v4.0.1 |  |
| `soc2` | SOC 2 — customers will ask for the report |  |
| `iso` | ISO/IEC 27001 |  |
| `sector` | A sector regulator (central bank, health authority, education ministry) |  |
| `none` | None that I know of |  |
| `__other` | Other — specify | Free text in the `other` map |

### J2 — Do you need to prove, later, that a specific person consented to a specific thing?

- Type: single-select, required
- Why it is asked: GDPR Article 7(1) requires the controller to be able to demonstrate consent. A boolean column cannot demonstrate anything.

| Code | Answer | Note |
|---|---|---|
| `no` | No — we rely on contract or legitimate interests throughout |  |
| `simple` | Yes — one overall consent |  |
| `purpose` | Yes — separately per purpose, with independent withdrawal |  |
| `versioned` | Yes — per purpose, and tied to the exact wording shown at the time |  |
| `__other` | Other — specify | Free text in the `other` map |

### J3 — Must you honour deletion requests?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `soft` | Yes — deactivate and hide |  |
| `anon` | Yes — irreversibly anonymise, keeping records we must retain | Usually the only lawful answer when financial or clinical records exist. |
| `hard` | Yes — actually destroy the rows |  |
| `crypto` | Yes — by destroying the per-subject encryption key |  |
| `__other` | Other — specify | Free text in the `other` map |

### J4 — Is there a data residency requirement?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `contract` | Only because customers ask for it in contracts |  |
| `law` | Yes — the law requires local storage |  |
| `transfer` | Not storage, but cross-border transfers need a lawful mechanism |  |
| `unsure` | Not sure |  |
| `__other` | Other — specify | Free text in the `other` map |

### J5 — How long must core records be kept?

- Type: single-select, required
- Why it is asked: Different classes almost always have different clocks. Answer for the longest legally mandated one.

| Code | Answer | Note |
|---|---|---|
| `short` | As short as possible — delete when no longer needed |  |
| `y1` | About 1 year |  |
| `y6` | 5 – 7 years | Typical accounting, tax and HIPAA-style clocks. |
| `y10` | 10+ years | Financial services, clinical records, pensions. |
| `perm` | Permanently — statutory or archival records |  |
| `mixed` | Different classes have very different clocks |  |
| `__other` | Other — specify | Free text in the `other` map |

### J6 — How will you handle children’s data?

- Type: single-select, required
- Shown when: `has('A2','minor')||has('A5','child')||has('A1','edu')`

| Code | Answer | Note |
|---|---|---|
| `block` | We block under-age users entirely |  |
| `parent` | Verifiable parental consent before processing |  |
| `school` | The school or institution provides the lawful basis |  |
| `reduced` | Reduced processing and no profiling for under-age accounts |  |
| `__other` | Other — specify | Free text in the `other` map |

### J7 — Do you understand your breach-notification clock?

- Type: single-select, required
- Why it is asked: These clocks differ sharply. Nigeria’s GAID Article 33 requires the data subject to be told immediately in high-risk cases; GDPR gives 72 hours to the regulator; HIPAA gives 60 days.

| Code | Answer | Note |
|---|---|---|
| `yes` | Yes — documented, with an owner and a rehearsed process |  |
| `partly` | Roughly, but it is not rehearsed |  |
| `no` | No |  |
| `__other` | Other — specify | Free text in the `other` map |

### J8 — Do third parties process this data on your behalf?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `few` | A few — hosting, email, analytics |  |
| `many` | Many, including sub-processors of sub-processors |  |
| `share` | We also share data with independent controllers | A materially different legal relationship — and a different table. |
| `__other` | Other — specify | Free text in the `other` map |

## Section K — Audit & evidence

What you must be able to prove after the fact, to whom, and for how long.

### K1 — What must you be able to reconstruct after the fact?

- Type: multi-select, required
- Why it is asked: Each selection is a specific query your schema must be able to answer, and each has a cost.

| Code | Answer | Note |
|---|---|---|
| `authn` | Every sign-in, failure and MFA challenge |  |
| `access` | Every read of a sensitive record | The expensive one. Required by HIPAA-style regimes. |
| `change` | Every change to a record, with before and after values |  |
| `perm` | Every permission grant, revocation and role change |  |
| `admin` | Every administrative and configuration action |  |
| `money` | Every financial movement, immutably |  |
| `export` | Every export or bulk download |  |
| `imperson` | Every impersonated action, attributed to both identities |  |
| `consent` | Every consent given and withdrawn |  |
| `__other` | Other — specify | Free text in the `other` map |

### K2 — How long must the audit trail be kept, and how much of it must be instantly searchable?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `d90` | 90 days |  |
| `y1` | 12 months, with 3 months immediately available | The PCI DSS requirement. |
| `y6` | 6 years | The HIPAA requirement. |
| `y7` | 7 – 10 years |  |
| `perm` | Indefinitely |  |
| `__other` | Other — specify | Free text in the `other` map |

### K3 — Must the audit trail resist tampering by your own privileged staff?

- Type: single-select, required
- Why it is asked: In PostgreSQL an append-only trigger does not stop a table owner or superuser. Only shipping records off-box to separately controlled storage does.

| Code | Answer | Note |
|---|---|---|
| `no` | No — honest-mistake protection is enough |  |
| `append` | Application-level append-only is enough |  |
| `offbox` | Yes — records must be shipped to separately controlled storage |  |
| `crypto` | Yes — plus cryptographic chaining or a WORM store |  |
| `__other` | Other — specify | Free text in the `other` map |

### K4 — Will you be asked “who had access to this, on this date, and who approved it?”

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `rare` | Rarely — in an incident |  |
| `routine` | Routinely — auditors, regulators or customers ask |  |
| `contract` | Contractually, within a fixed response time |  |
| `__other` | Other — specify | Free text in the `other` map |

## Section L — Operations & stack

Team, hosting, language and budget. This decides ORM, managed-vs-self, and how much of the above you should buy.

### L1 — Who will operate this database?

- Type: single-select, required
- Why it is asked: The honest answer here overrides almost every clever recommendation elsewhere.

| Code | Answer | Note |
|---|---|---|
| `solo` | One or two generalist developers, no DBA |  |
| `small` | A small team with one person who is comfortable with SQL |  |
| `plat` | A platform or infrastructure team |  |
| `dba` | A dedicated database or SRE function |  |
| `__other` | Other — specify | Free text in the `other` map |

### L2 — How will it be hosted?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `managed` | Managed cloud database service |  |
| `vm` | Our own virtual machines |  |
| `k8s` | Kubernetes with an operator |  |
| `serverless` | Serverless / edge platform |  |
| `onprem` | On-premises or private cloud | Sometimes non-negotiable in health, government and banking. |
| `hybrid` | Hybrid — some on-premises, some cloud |  |
| `__other` | Other — specify | Free text in the `other` map |

### L3 — Which platform?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `aws` | AWS |  |
| `gcp` | Google Cloud |  |
| `azure` | Azure |  |
| `other` | Another provider (Hetzner, DigitalOcean, OVH, local provider) |  |
| `own` | Our own hardware |  |
| `undecided` | Undecided |  |
| `__other` | Other — specify | Free text in the `other` map |

### L4 — What availability does the business actually need?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `a1` | Best effort — hours of downtime are survivable |  |
| `a2` | 99.9% — under an hour a month |  |
| `a3` | 99.95% or better, with automated failover |  |
| `a4` | Continuous — a failed write is a business incident |  |
| `__other` | Other — specify | Free text in the `other` map |

### L5 — How much data may you lose in a disaster, and how quickly must you be back?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `r1` | A day of data; back within a day |  |
| `r2` | An hour of data; back within hours |  |
| `r3` | Minutes of data; back within an hour |  |
| `r4` | Zero data loss | Requires synchronous replication and the latency cost that comes with it. |
| `__other` | Other — specify | Free text in the `other` map |

### L6 — What is the primary application language?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `ts` | TypeScript / Node |  |
| `py` | Python |  |
| `go` | Go |  |
| `rust` | Rust |  |
| `jvm` | Java or Kotlin |  |
| `dotnet` | C# / .NET |  |
| `ruby` | Ruby |  |
| `php` | PHP |  |
| `elixir` | Elixir |  |
| `mixed` | Several, deliberately |  |
| `__other` | Other — specify | Free text in the `other` map |

### L7 — What is your position on ORMs?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `full` | A full ORM — we want objects, not rows |  |
| `light` | A query builder or lightweight mapper |  |
| `sql` | Hand-written SQL with generated types |  |
| `mixed` | An ORM for CRUD, raw SQL for the hard paths | What most successful teams converge on. |
| `open` | No strong view — recommend one |  |
| `__other` | Other — specify | Free text in the `other` map |

### L8 — How disciplined is your schema-change process?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `auto` | The framework syncs the schema automatically | Fine in development. Not a production migration strategy. |
| `gen` | Generated migrations, reviewed in pull requests |  |
| `hand` | Hand-written, reviewed, with an explicit rollback path |  |
| `expand` | Expand/contract with zero-downtime discipline |  |
| `none` | No process yet |  |
| `__other` | Other — specify | Free text in the `other` map |

### L9 — How price-sensitive is the infrastructure budget?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `tight` | Very — every pound counts |  |
| `normal` | Normal — value for money |  |
| `flex` | Flexible — correctness and speed outrank cost |  |
| `__other` | Other — specify | Free text in the `other` map |

### L10 — How long until this must be in production?

- Type: single-select, required

| Code | Answer | Note |
|---|---|---|
| `weeks` | Weeks |  |
| `q` | A quarter |  |
| `half` | Six months or more |  |
| `live` | It is already live and we are correcting course |  |
| `__other` | Other — specify | Free text in the `other` map |

### L11 — Would you rather build authentication yourself or buy it?

- Type: single-select, required
- Why it is asked: Buying removes most of the security-critical authentication work. It removes far less of the user, role and organisation modelling — no major vendor models an organisational hierarchy for you.

| Code | Answer | Note |
|---|---|---|
| `build` | Build — we want full control and no per-user cost |  |
| `buy` | Buy — we want passkeys, SSO and recovery handled |  |
| `buysso` | Build the core, buy enterprise SSO/SCIM as an add-on |  |
| `open` | No view — recommend one |  |
| `__other` | Other — specify | Free text in the `other` map |

## Section X — Domain specifics

Extra questions triggered by the domain you chose in section A. Skipped entirely if none apply.

### X-FIN1 — How is money represented?

- Type: single-select, required
- Shown when: `has('A1','fintech')||has('A5','funds')`
- Why it is asked: There is one correct answer to this in a system that holds funds, and it is not “a balance column”.

| Code | Answer | Note |
|---|---|---|
| `balance` | A balance column updated in place | Unauditable and unreconcilable. Expect the recommendation to argue against it. |
| `ledger` | An immutable double-entry ledger; balances are derived |  |
| `ledgerbal` | A double-entry ledger plus materialised balances for speed |  |
| `external` | A third-party ledger or core banking system holds the truth |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-FIN2 — Do transaction limits and approval thresholds vary by person, role or customer tier?

- Type: single-select, required
- Shown when: `has('A1','fintech')||has('A5','funds')`

| Code | Answer | Note |
|---|---|---|
| `no` | No — fixed global limits |  |
| `role` | By role |  |
| `tier` | By customer KYC tier |  |
| `both` | By both, plus per-account overrides | Limits become an authorization attribute, not a config constant. |
| `__other` | Other — specify | Free text in the `other` map |

### X-FIN3 — How many KYC or verification tiers are there?

- Type: single-select, required
- Shown when: `has('A1','fintech')||has('A5','funds')`

| Code | Answer | Note |
|---|---|---|
| `one` | One — verified or not |  |
| `few` | 2 – 3 tiers with different limits |  |
| `many` | Several, varying by product and jurisdiction |  |
| `na` | Not applicable |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-FIN4 — Must you reconcile against an external source of truth?

- Type: single-select, required
- Shown when: `has('A1','fintech')||has('A5','funds')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `daily` | Yes — daily settlement files or bank statements |  |
| `rt` | Yes — near real time against a scheme or processor |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-HLT1 — How is clinical access decided?

- Type: single-select, required
- Shown when: `has('A1','health')||has('A5','phi')`
- Why it is asked: Role alone almost never works in healthcare: the same nurse may see one patient and not another. The usual answer is role plus a current care relationship.

| Code | Answer | Note |
|---|---|---|
| `role` | By professional role alone |  |
| `care` | By an active care relationship with the patient |  |
| `unit` | By the ward, clinic or service the patient is under |  |
| `combo` | Role, plus care relationship, plus location, plus period |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-HLT2 — Do you need emergency override of access controls?

- Type: single-select, required
- Shown when: `has('A1','health')||has('A5','phi')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `break` | Yes — break-glass with a recorded reason and immediate alerting | Access is granted, then justified, then reviewed. Never silently. |
| `dual` | Yes — with a second clinician’s authorisation |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-HLT3 — How granular is patient consent to sharing?

- Type: single-select, required
- Shown when: `has('A1','health')||has('A5','phi')`

| Code | Answer | Note |
|---|---|---|
| `none` | Not modelled |  |
| `global` | One share/do-not-share flag |  |
| `org` | Per receiving organisation |  |
| `fine` | Per data category, per recipient, with a validity period |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-HLT4 — Do you exchange data with other clinical systems?

- Type: single-select, required
- Shown when: `has('A1','health')||has('A5','phi')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `fhir` | Yes — HL7 FHIR |  |
| `hl7v2` | Yes — HL7 v2 messaging |  |
| `files` | Yes — files or a national spine |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-B2B1 — What is the largest tenant likely to be, relative to the median?

- Type: single-select, required
- Shown when: `has('A1','b2bsaas')||anyOf('A3','shared','schema','hybrid')`
- Why it is asked: The noisy-neighbour question. If one tenant is 1000× the median, shared-everything designs stop working before you notice.

| Code | Answer | Note |
|---|---|---|
| `even` | Broadly similar sizes |  |
| `x10` | Up to about 10× the median |  |
| `x100` | 100× or more | Plan tenant-level partitioning or isolation from the start. |
| `unk` | Unknown |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-B2B2 — Do you need guest or external-collaborator access inside a tenant?

- Type: single-select, required
- Shown when: `has('A1','b2bsaas')||anyOf('A3','shared','schema','hybrid')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `guest` | Yes — a distinct guest class with reduced default visibility |  |
| `cross` | Yes — and one person may be a guest in many tenants at once |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-B2B3 — How do tenants get deleted or exported?

- Type: single-select, required
- Shown when: `has('A1','b2bsaas')||anyOf('A3','shared','schema','hybrid')`

| Code | Answer | Note |
|---|---|---|
| `manual` | Manually, by us, on request |  |
| `self` | Self-service export and deletion |  |
| `contract` | Contractual — within a fixed window, with a certificate |  |
| `notyet` | Not thought about it | It will be asked in the first enterprise security review. |
| `__other` | Other — specify | Free text in the `other` map |

### X-COM1 — Is inventory tracked, and where?

- Type: single-select, required
- Shown when: `has('A1','commerce')`

| Code | Answer | Note |
|---|---|---|
| `none` | No physical inventory |  |
| `single` | One location |  |
| `multi` | Multiple warehouses or stores | Stock becomes a per-location ledger, not a column. |
| `thirdparty` | A third-party system is authoritative |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-COM2 — Is there a physical point of sale?

- Type: single-select, required
- Shown when: `has('A1','commerce')`

| Code | Answer | Note |
|---|---|---|
| `no` | Online only |  |
| `pos` | Yes — staff use a till or handheld |  |
| `both` | Yes, and stock and orders must be consistent across both |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-COM3 — Is it a marketplace with independent sellers?

- Type: single-select, required
- Shown when: `has('A1','commerce')`

| Code | Answer | Note |
|---|---|---|
| `no` | No — we own all the stock |  |
| `yes` | Yes — sellers manage their own catalogue and staff | Each seller is effectively a tenant with its own privilege ladder. |
| `mixed` | Mixed — our stock plus third-party sellers |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-LOG1 — How is a field worker’s identity tied to their legal entitlement to work?

- Type: single-select, required
- Shown when: `has('A1','logistics')`
- Why it is asked: Where a licence or certification governs the work, the identity record and the credential record are separate objects with separate expiry.

| Code | Answer | Note |
|---|---|---|
| `na` | No licence or certification involved |  |
| `track` | We record licence or certification numbers and expiry |  |
| `block` | Expired credentials must block assignment automatically |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-LOG2 — Do you capture high-frequency telemetry (positions, sensor readings, scans)?

- Type: single-select, required
- Shown when: `has('A1','logistics')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `low` | Occasional events — scans, status changes |  |
| `high` | Continuous streams from vehicles or devices | This is a separate storage problem from your entity data. |
| `__other` | Other — specify | Free text in the `other` map |

### X-EDU1 — Is access bounded by academic periods?

- Type: single-select, required
- Shown when: `has('A1','edu')`
- Why it is asked: Enrolment is dated. A teacher’s access to last year’s class is a different fact from their access this year.

| Code | Answer | Note |
|---|---|---|
| `no` | No — access is continuous |  |
| `term` | Yes — by term, semester or academic year |  |
| `course` | Yes — per course or cohort enrolment period |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-EDU2 — Do guardians have their own access to a learner’s record?

- Type: single-select, required
- Shown when: `has('A1','edu')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `view` | Yes — read-only |  |
| `act` | Yes — and they can act (consent, pay, communicate) |  |
| `age` | Yes, until the learner reaches an age threshold, then it lapses | A dated relationship with an automatic end. |
| `__other` | Other — specify | Free text in the `other` map |

### X-GOV1 — Are there statutory records-management obligations?

- Type: single-select, required
- Shown when: `has('A1','gov')||has('A5','gov')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `sched` | Yes — a published retention and disposal schedule |  |
| `arch` | Yes — plus transfer to a national archive |  |
| `__other` | Other — specify | Free text in the `other` map |

### X-GOV2 — Are records subject to public access or freedom-of-information requests?

- Type: single-select, required
- Shown when: `has('A1','gov')||has('A5','gov')`

| Code | Answer | Note |
|---|---|---|
| `no` | No |  |
| `foi` | Yes — FOI requests must be servable |  |
| `open` | Yes — some data is published openly | Then a publication classification belongs on the record itself. |
| `__other` | Other — specify | Free text in the `other` map |

### X-SOC1 — What is the moderation and trust-and-safety model?

- Type: single-select, required
- Shown when: `has('A1','social')`

| Code | Answer | Note |
|---|---|---|
| `light` | Report-and-review only |  |
| `team` | A dedicated moderation team with tiered powers |  |
| `comm` | Community moderators with scoped powers | Scoped moderation is relationship-based authorization. |
| `auto` | Automated classification plus human appeal |  |
| `__other` | Other — specify | Free text in the `other` map |
