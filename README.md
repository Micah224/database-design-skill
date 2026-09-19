# database-design-skill

Evidence-based database requirements discovery before any schema: 50+ branching questions across users, staff/departments/branches, admins and super-admin, then a cited stack recommendation, contradiction check and tested PostgreSQL schema. Use for any database, schema, data-model, RBAC, multi-tenancy, audit or consent design.

This repository packages the `database-design-discovery` Agent Skill.

## What it does

A schema is a set of bets about who is in the system, what they may do, and what you will be asked to prove later — and most of those bets are expensive to reverse. The skill makes them explicit before the first migration, using a deterministic rule engine rather than recall:

- **113 questions** (83 unconditional, the rest opened by earlier answers) across domain and risk, user populations, staff and org structure, admin tiers, regulation, retention and scale.
- **74 decision rules and 31 conflict rules**, every one citing a primary source — NIST SP 800-63-4, ANSI/INCITS 359 RBAC, PostgreSQL documentation, GDPR/NDPA/POPIA/HIPAA text, published benchmarks.
- The same answers always produce the same brief.

## Layout

```
skills/database-design-discovery/
├── SKILL.md                  # entry point and workflow
├── references/               # question bank, decision rules, conflict rules, evidence,
│                             #   schema guide, design principles, domain playbooks
├── scripts/                  # questions.js, check-answers.js, recommend.js, engine.js
└── assets/                   # offline HTML questionnaire, reference schema,
                              #   schema tests, decision matrix, example answers
```

## Install

Clone the bundled folder into your skills directory:

```bash
git clone https://github.com/Micah224/database-design-skill
cp -R database-design-skill/skills/database-design-discovery ~/.claude/skills/
```

Then ask for a database, schema, RBAC or multi-tenancy design and the skill triggers on its own.

## Use it directly

The scripts are plain Node with no dependencies and no network access. Run them from `skills/database-design-discovery/`:

```bash
node scripts/questions.js                          # list questions for the next section
node scripts/check-answers.js answers.json         # validate an answers file
node scripts/recommend.js answers.json --out design-brief.md
```

`assets/answers.example.json` is a complete worked answer set if you want to see the output shape first. For self-service, hand someone `assets/database-design-questionnaire.html` — it runs the same engine entirely offline in a browser and exports an answers file.

Keep `answers.json` alongside the schema: it is the audit trail for why the schema looks the way it does.
