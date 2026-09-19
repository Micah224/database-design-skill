# Agent instructions for this repository

This repository ships one **Agent Skill** in the open `SKILL.md` format:

- `skills/database-design-discovery/SKILL.md` — evidence-based requirements discovery and stack recommendation to run **before** designing a database schema: the full privilege ladder (users → staff/departments/branches → admins → super-admin), identity and authentication, authorization model, multi-tenancy, audit, privacy/compliance and operations.

## When to use it

Load and follow `skills/database-design-discovery/SKILL.md` whenever the task involves any of:

- designing, reviewing or migrating a database schema, data model or ERD;
- choosing a database (PostgreSQL vs MySQL vs SQLite vs MongoDB vs a distributed SQL engine) or answering "what database should I use";
- users, roles, permissions, RBAC/ABAC/ReBAC, multi-tenant isolation, row-level security;
- how admins, staff, departments, branches, custom roles or break-glass access should be modelled;
- audit logging, consent, erasure, retention or breach-notification requirements in the data layer.

Follow the skill's workflow in order: interview (or import answers) → validate → recommend → resolve contradictions → design from the reference schema → prove with the tests → deliver the brief, the schema and the answers file together.

## How to run the tooling

All scripts are plain Node.js (18+), no dependencies, no network:

```bash
node skills/database-design-discovery/scripts/questions.js --section A
node skills/database-design-discovery/scripts/check-answers.js answers.json
node skills/database-design-discovery/scripts/recommend.js answers.json --out design-brief.md
```

The reference schema and its 29-assertion test suite need PostgreSQL 16+ (optional):

```bash
createdb reftest
psql -d reftest -v ON_ERROR_STOP=1 -f skills/database-design-discovery/assets/reference-schema.sql
psql -d reftest -f skills/database-design-discovery/assets/schema-tests.sql
```

## Rules of evidence (apply to any agent using this repo)

- Every recommendation in a deliverable carries a source. The engine prints "no source recorded" where it has none; hold your own additions to the same standard.
- Do not silently override the engine. Disagree in writing, with a citation.
- Two claims in the evidence register are marked unverified (Nigeria GAID Art. 33 wording; PCI DSS 10.2.2/10.5.1 text). Keep the marking.
- Regime summaries are a design aid, not legal advice.
