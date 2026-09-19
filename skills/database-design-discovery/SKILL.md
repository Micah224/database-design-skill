---
name: "database-design-discovery"
description: "Evidence-based database requirements discovery before any schema: 50+ branching questions across users, staff/departments/branches, admins and super-admin, then a cited stack recommendation, contradiction check and tested PostgreSQL schema. Use for any database, schema, data-model, RBAC, multi-tenancy, audit or consent design."
---

# Database design discovery

A database schema is a set of bets about who is in the system, what they may do, and what you will be asked to prove later. Most of those bets are expensive to reverse — adding a tenant column to a live schema, recording history you did not record, splitting a `users` table from an `admins` table — and they are usually made implicitly on day one. This skill makes them explicit, on purpose, from evidence, before the first migration.

The core of it is a deterministic rule engine: a question bank (113 questions, 83 unconditional, the rest opened by earlier answers) and 74 decision rules plus 31 conflict rules, every one of which cites a primary source (NIST SP 800-63-4, ANSI/INCITS 359 RBAC, PostgreSQL docs, GDPR/NDPA/POPIA/HIPAA text, published benchmarks). The same answers always produce the same brief. Your job is to get honest answers in, read the output critically, and turn it into a schema — not to substitute your own preferences for the rules.

## Workflow

```
1. Choose a mode      → interview / self-service HTML / import an answers file
2. Interview          → node scripts/questions.js …   (ask by section; record codes)
3. Validate           → node scripts/check-answers.js answers.json
4. Recommend          → node scripts/recommend.js answers.json --out design-brief.md
5. Resolve conflicts  → contradictions first, with the user, before any design
6. Design the schema  → checklist → references/schema-guide.md → assets/reference-schema.sql
7. Prove it           → apply + run assets/schema-tests.sql (if PostgreSQL is available)
8. Deliver            → brief + schema + answers.json (the audit trail)
```

Run the scripts from the skill directory (or give absolute paths). They are plain Node, no dependencies, no network.

If this file was installed on its own — no `scripts/`, `references/` or `assets/` beside it — fetch the bundled folder first: the `database-design-discovery.skill` package or the `db-design-discovery` repository (`skills/database-design-discovery/`). Without the engine you can still run the interview from `references/question-bank.md` and apply `references/decision-rules.md` and `references/conflict-rules.md` by hand, but say so in the brief; the scripts exist precisely so that the recommendation is deterministic rather than recalled.

### 1. Choose a mode

- **Interview** (default when the user is present): you ask the questions in conversation and record the answers. Best quality, because you can probe.
- **Self-service**: the user prefers to answer alone. Give them `assets/database-design-questionnaire.html` — it runs entirely offline in a browser, has the same engine, and exports `db-questionnaire-answers.json`. Then continue from step 3 with that file.
- **Import**: the user already has an answers file from a previous run. Go to step 3. Re-running after a material change (new market, new regime, a large customer) is a legitimate and valuable use.

If the user is unattended or has said "just make reasonable assumptions", still run the interview against what you know from the codebase, docs and conversation; record every assumed answer with a note saying it was assumed, and say so at the top of the brief. Assumed answers are acceptable; hidden assumptions are not.

### 2. Interview

Get the question list for a section, ask it, record codes, repeat. Later sections depend on earlier answers (domain-specific questions in section X only appear once section A is answered), so always regenerate the list after recording:

```bash
node scripts/questions.js --section A                      # first pass
node scripts/questions.js --answers answers.json --unanswered   # what is still open, given what you know
node scripts/questions.js --answers answers.json --section X    # branch questions now visible
```

How to run it well:

- **Ask a section at a time, not 113 questions at once.** Sections are 4–11 questions and each has a one-line purpose; give that purpose, then the questions with their options. People answer better when they know why they are being asked.
- **Record the option *codes*** (the backtick values `questions.js` prints) in `answers.json`, as `{"A1": "fintech", "A2": ["public","ownstaff"]}` — a string for single-select, an array for multi-select. The file shape the HTML tool exports (`{"answers": {...}, "other": {...}, "notes": {...}}`) is also accepted.
- **Every question accepts `__other`.** When none of the options fit, record `"__other"` and put the user's own words verbatim in the `other` map under the question id. It is carried into the brief and flagged for a human decision. Do not force a nearby option; the whole point of a free-text answer is that the rules cannot see it, so a person must.
- **Use `notes` for context** — decisions already taken, who was consulted, constraints. They appear in the brief's answer table, which becomes the design's audit trail.
- **Do not skip sections that seem irrelevant.** Section J (privacy) applies to an internal tool because employees are data subjects; section G (staff) applies to a consumer app the moment there is a support desk. The branching already removes what genuinely does not apply.
- **Push back on aspirational answers.** The most common failure is selecting the policy the user *intends* rather than the one they will *ship* ("we'll require MFA" when the login page today has none). Ask for the shipping answer; put the aspiration in `notes`.
- **Multi-population systems** (customers *and* staff *and* partners) meet several single-select questions — proofing level, assurance level, recovery route, session length. Answer for the **highest-risk population** (usually staff or administrators), and record the other populations' answers in `notes` on that question; the design then treats the stricter setting as the ceiling and you relax it per population in the schema. Do not use `__other` for this — it costs rule coverage.
- If the user has an existing codebase, answer what you can from it first (the ORM in use, the migration discipline, the login handle, whether there is a `tenant_id`) and confirm rather than ask.

Fill the answers file incrementally; you can validate at any point.

### 3. Validate

```bash
node scripts/check-answers.js answers.json    # exit 0 = complete
```

It lists unknown codes, `__other` answers missing their text, and every visible required question still unanswered. Fix those before recommending. `recommend.js` refuses a partial file unless you pass `--allow-partial`, and then marks the brief as partial — use that only when the user has explicitly accepted an incomplete run.

### 4. Recommend

```bash
node scripts/recommend.js answers.json --out design-brief.md      # Markdown for humans
node scripts/recommend.js answers.json --format json               # for further processing
```

Read the brief top to bottom before showing it. It has four parts, deliberately ordered:

1. **Conflicts and risks** — 31 rules that fire on *combinations* of answers. A *contradiction* means two answers cannot both be satisfied (e.g. hard deletion + a 10-year retention obligation; MFA login + an emailed reset link). A *risk* needs a deliberate decision. A *consideration* is a suggestion.
2. **The stack** — up to 18 decision areas (the eighteenth, *Domain-specific requirements*, appears when section X or the staff operating-condition questions produced checklist items). Each gives one primary, one alternative, **the condition under which to switch**, the answers that produced it, and its source. A line with no source is printed as unsupported.
3. **What the schema must contain** — tables and constraints that exist because of specific answers, not a generic best-practice list.
4. **The answers** — the complete input, with notes and custom text.

### 5. Resolve conflicts before designing

Contradictions are not warnings to note in passing: they mean the design cannot satisfy the requirements as stated, and one of them will be breached in production. Take each contradiction back to the user with the "What to do" line, get a decision, update `answers.json`, and re-run. Only design from a brief with zero contradictions (risks may remain if the user has accepted them explicitly — record that in `notes`).

### 6. Design the schema

Start from the checklist in the brief, not from a blank page. Open `references/schema-guide.md`: it maps each checklist group to a part of `assets/reference-schema.sql` and says how to cut the schema down. Take the parts the checklist names, adapt names and types to the domain, and delete everything else — an unused table still has to be migrated, secured and explained.

Non-negotiables that the reference schema encodes and that you should keep whatever else you change, because each is the reversal of a documented, expensive mistake:

- **One `principal` table** for every kind of actor, with status as a six-state enum, never `is_active`. Separate users/admins/staff tables make every cross-cutting query a UNION and the audit trail polymorphic.
- **The grant is the unit of privilege**: `(principal, role, scope node, inheritable, active|eligible, valid period, granted_by, justification, approval)`. This single row shape is what prevents role explosion (`branch_manager_lagos`, `branch_manager_abuja`, …) and answers auditors.
- **Validity periods (`tstzrange`) with exclusion constraints** on assignments, memberships and edges wherever the brief says history must be reconstructible. History you did not record does not exist.
- **Permissions as a registry** (`action × resource_type`), roles as data, custom roles as base + delta.
- **Federated identity joined on `(issuer, subject)`**, never on email.
- **Authenticators as rows**, with per-authenticator failure counters and the WebAuthn credential fields.
- **Consent as an append-only event log** tied to a hashed notice version; current state as a view.
- **Audit written in the same transaction**, with two actor columns (whose permissions, who was at the keyboard), and the honest caveat that an append-only trigger constrains the application, not a table owner.
- **Row-level security as a backstop**: RESTRICTIVE policies, FORCE, application role does not own the tables, tenant read as `(SELECT core.current_tenant())`.

If the brief recommended something other than PostgreSQL, the patterns still apply; the exclusion constraints, `ltree` and row-level security do not, and you enforce overlap and scope inheritance in application code. Say so in the design.

### 7. Prove it

If PostgreSQL 16+ is available:

```bash
createdb reftest
psql -d reftest -v ON_ERROR_STOP=1 -f assets/reference-schema.sql
psql -d reftest -f assets/schema-tests.sql 2>&1 | grep -E "PASS|FAIL"     # expect 29 PASS, 0 FAIL; re-runnable (it rolls itself back)
```

Then write the same kind of test for the schema you actually produced: try to violate each constraint you claim (overlapping assignments, self-approval, a tampered approval payload, a cross-tenant read as the application role). Constraints you have not tried to violate are constraints you are assuming. Keep the six "proof" queries at the end of the reference schema as integration tests, adapted to your names.

### 8. Deliver

Deliver three things together: `design-brief.md`, the schema (SQL or migrations), and `answers.json`. The answers file is not a by-product; it is the record of why the database looks the way it does, and it lets the whole thing be re-run when circumstances change.

## Rules of evidence

- **Do not override the engine silently.** If you disagree with a recommendation, say so in the brief, give the reason, and cite something. The rules are deterministic and cited precisely so that disagreement is visible and arguable.
- **No unsourced claims in the deliverable.** The engine prints "no source recorded" where it has none; hold your own additions to the same standard. `references/evidence.md` lists everything the engine can cite.
- **Two claims are marked unverified** in the evidence (Nigeria GAID Art. 33 subject-notification wording; PCI DSS 10.2.2/10.5.1 text). Carry the marking through; do not present them as confirmed.
- **Standards status matters.** OAuth 2.1 is an Internet-Draft, not an RFC (cite RFC 9700). WebAuthn Level 3 is a Candidate Recommendation Snapshot, not a Recommendation (Level 2 is). Say which you target.
- **Version and lifecycle claims age.** Evidence is current as at the date in the frontmatter. Re-check anything you quote if that date is more than a few months old.
- **Not legal advice.** Regime clocks and erasure rules are summarised because they become tables and columns; tell the user to confirm them for their jurisdictions.

## Reference map

Read these when the step calls for them; not all at once.

| File | Read it when |
|---|---|
| `references/question-bank.md` | You want the catalogue of codes without running the script, or need to explain why a question exists. |
| `references/decision-rules.md` | Reviewing or explaining a stack recommendation; checking what would change it. |
| `references/conflict-rules.md` | A conflict fired and you need the full condition; or you want to pre-empt one during the interview. |
| `references/schema-guide.md` | Step 6 — always. Maps checklist → schema parts, and says how to cut the schema down. |
| `references/design-principles.md` | The user asks *why* one people table, why status is an enum, or which decisions are expensive to reverse. |
| `references/domain-playbooks.md` | The domain is fintech, B2B SaaS, healthcare, commerce/POS, logistics, education or government — the load-bearing questions per domain. |
| `references/authenticators.md` | Choosing authenticators, recovery paths or session policy; the AAL/reauthentication figures. |
| `references/regime-clocks.md` | Anything touching breach notification, erasure, residency or retention. |
| `references/evidence.md` | You need to cite, or the user challenges a claim. |

Assets: `assets/reference-schema.sql` (the schema), `assets/schema-tests.sql` (29 assertions, re-runnable), `assets/database-design-questionnaire.html` (self-service tool, same engine), `assets/decision-matrix.xlsx` (the rules as an auditable spreadsheet with live conflict formulas), `assets/answers.example.json` (a complete worked example: mid-size B2B SaaS).

## Brief format

`recommend.js` produces this; keep the same sections if you post-edit it:

```
# Database design brief
## 1. Conflicts and risks in the answers     (contradictions → risks → considerations)
## 2. Recommended stack                        (2.1 … 2.18: primary / alternative / switch when / why / source)
## 3. What the schema must contain            (grouped checklist, derived from answers)
## 4. Answers                                  (id, question, answer, note — the audit trail)
```

## Example

**User:** "We're building a clinic management SaaS for UK and US practices. Clinicians, admin staff, patients and carers all log in. Need a schema."

**With this skill:** ask sections A–L (about 90 questions once branches open; section X adds healthcare and B2B questions), recording e.g. `A1: health`, `A3: shared`, `C7: [carer, poa, staffimp]`, `I1: [role, unit, rel, assign, consent]`, `K1: [..., access]`. `check-answers.js` passes. `recommend.js` produces: shared-schema tenancy with RESTRICTIVE RLS; passkeys with device-bound keys for admins; relationship-based access (role + active care relationship + location + period) with OpenFGA/SpiceDB or a closure table as the alternative; one org node/edge model with validity periods; read-access audit at query-intent level; per-purpose consent events; HIPAA six-year and GDPR retention classes — each with its source. One risk fires ("no account deletion under an erasure regime") because E1 omitted `delete`; you resolve it with the user, re-run, then build the schema from Parts 1, 2, 3, 4, 5, 6, 9 and 10 of the reference schema and run the tests.

**Without it:** a `users` table with `is_admin`, a `roles` string column, no validity periods, email as the federated key, and an audit log added in month nine after the first data-subject request.