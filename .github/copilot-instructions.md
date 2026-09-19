# GitHub Copilot instructions

This repository ships an Agent Skill at `skills/database-design-discovery/SKILL.md`.

Before designing, reviewing or migrating a database schema, choosing a database engine, or modelling users, roles, permissions, multi-tenancy, staff/departments/branches, administrators, audit logging or consent, read that file and follow its workflow: run the discovery questions (`scripts/questions.js`), validate the answers (`scripts/check-answers.js`), generate the brief (`scripts/recommend.js`), resolve contradictions with the user, then design from `assets/reference-schema.sql` using `references/schema-guide.md`.

`AGENTS.md` at the repository root has the full trigger list and commands. Do not add unsourced recommendations to a deliverable; the engine cites every rule and so should you.
