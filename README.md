# Database Design Discovery — an Agent Skill

**Ask the fifty-plus questions before the first migration.** This skill turns database design from a guessing exercise into a structured, evidence-based discovery: a branching interview across the whole privilege ladder (users → staff, departments and branches → administrators → super-admin/break-glass), identity and authentication, the authorization model, multi-tenancy, audit, privacy/compliance and operations — and then a deterministic, **cited** recommendation: for each of up to 18 decisions, one primary choice, one alternative, and the condition under which to switch. Plus a contradiction check, a schema checklist derived from your answers, and a tested PostgreSQL reference schema.

It is written in the open **Agent Skills** format (`SKILL.md` + `scripts/` + `references/` + `assets/`), so the same folder works in Claude Code and Claude Desktop, OpenAI Codex, GitHub Copilot, Gemini CLI, Cursor and any agent that reads `AGENTS.md`.

```
skills/database-design-discovery/
├── SKILL.md                      # the procedure an agent follows (≈170 lines)
├── scripts/
│   ├── engine.js                 # question bank + evidence + 74 decision rules + 31 conflict rules (no deps)
│   ├── questions.js              # list the questions to ask; branches open as answers are recorded
│   ├── check-answers.js          # validate an answers file (unknown codes, unanswered visible questions)
│   └── recommend.js              # answers.json → design brief (Markdown or JSON)
├── references/                   # loaded on demand by the agent
│   ├── question-bank.md          # all 113 questions with their answer codes
│   ├── decision-rules.md         # the answer → recommendation matrix
│   ├── conflict-rules.md         # the 31 combinations that fire as contradictions / risks
│   ├── schema-guide.md           # maps the checklist to parts of the reference schema
│   ├── design-principles.md      # one people table, status as a state machine, the grant as the unit of privilege…
│   ├── domain-playbooks.md       # fintech, B2B SaaS, healthcare, commerce/POS, logistics, education, government
│   ├── authenticators.md         # AAL ceilings, phishing resistance, schema fields per authenticator type
│   ├── regime-clocks.md          # GDPR / NDPA / Kenya / POPIA / HIPAA / CCPA / PCI side by side
│   └── evidence.md               # every source the engine cites
└── assets/
    ├── reference-schema.sql      # 1,331 lines, PostgreSQL 16+; 53 tables across core / privacy / audit
    ├── schema-tests.sql          # 29 assertions that prove the constraints fire (re-runnable)
    ├── database-design-questionnaire.html   # the same engine as a self-service, offline web form
    ├── decision-matrix.xlsx      # the rules as an auditable spreadsheet with live conflict formulas
    └── answers.example.json      # a complete worked example (mid-size B2B SaaS)
```

## Quick start (any agent, no install)

Clone or vendor this repository into your project. `AGENTS.md` at the root tells any agent when to use the skill and how. Then ask your agent:

> "We're building X. Run the database design discovery before we write the schema."

Or drive it by hand:

```bash
node skills/database-design-discovery/scripts/questions.js --section A            # start the interview
node skills/database-design-discovery/scripts/questions.js --answers answers.json --unanswered
node skills/database-design-discovery/scripts/check-answers.js answers.json
node skills/database-design-discovery/scripts/recommend.js answers.json --out design-brief.md
```

Or answer alone in a browser: open `assets/database-design-questionnaire.html` (works offline, nothing leaves the page) and export the answers as JSON.

`examples/` has a complete answers file and the brief it produces.

## Install as a skill

Requirements: Node.js 18+. PostgreSQL 16+ only if you want to run the schema tests.

```bash
git clone https://github.com/Micah224/database-design-skill
cd database-design-skill
./install.sh            # detects tools under $HOME and installs for each
./install.sh claude     # or name them: claude codex copilot gemini cursor agents
./install.sh --to ~/some/skills/dir
```

| Tool | User-scope location | Project-scope location | Also reads |
|---|---|---|---|
| Claude Code / Claude Desktop | `~/.claude/skills/database-design-discovery/` | `.claude/skills/database-design-discovery/` | `CLAUDE.md` |
| OpenAI Codex | `~/.codex/skills/…` or `~/.agents/skills/…` | `.codex/skills/…` or `.agents/skills/…` | `AGENTS.md` |
| GitHub Copilot (VS Code, CLI, coding agent) | `~/.copilot/skills/…` | `.github/skills/…` | `.github/copilot-instructions.md`, `AGENTS.md` |
| Gemini CLI | `~/.gemini/skills/…` | project skills dir | `GEMINI.md`, `AGENTS.md` |
| Cursor | `~/.cursor/skills/…` | `.cursor/skills/…` | `.cursor/rules/*.mdc`, `AGENTS.md` |
| Anything else | — | vendor `skills/` into the repo | `AGENTS.md` |

Paths reflect the tools as of September 2026; if your tool looks somewhere else, `--to` puts the folder wherever you need. The universal fallback needs no install at all: keep the repo (or just `skills/` + `AGENTS.md`) inside your project.

**Claude Desktop (Cowork) users:** you can also add the skill from the `.skill` package attached to the release, or paste `SKILL.md` into a new skill in Settings → Skills; the scripts and references then ship with it.

## What the skill actually does

1. **Interview** — 113 questions in 13 sections; 83 are always asked and the rest open up from earlier answers (a fintech answer in section A opens ledger and KYC questions in section X). Every question accepts "Other — specify", carried verbatim into the brief. The agent asks a section at a time and records answer codes in `answers.json`.
2. **Validate** — `check-answers.js` catches unknown codes and every visible required question still unanswered.
3. **Recommend** — `recommend.js` runs 74 decision rules and 31 conflict rules and writes the brief: contradictions and risks first, then the decisions (primary / alternative / switch-when / why / source), then the schema checklist, then the answers as the design's audit trail.
4. **Resolve** — contradictions (e.g. hard deletion + ten-year retention; MFA login + an emailed reset link) go back to the user before anything is designed.
5. **Design** — the checklist maps to parts of `reference-schema.sql`; the agent takes what is needed and deletes the rest.
6. **Prove** — apply the schema and run the 29 assertions; then write the same kind of test for the schema actually produced.

## The evidence standard

Every rule cites a primary source — NIST SP 800-63-4 (final, 31 July 2025), ANSI/INCITS 359-2012 (R2022), NIST SP 800-53 Rev. 5, W3C WebAuthn, IETF RFCs 8693 / 9700 / 7643 / 7644 / 9967, PostgreSQL documentation, GDPR / NDPA / Kenya DPA / POPIA / HIPAA / PCI DSS text, and published benchmarks and incident reports (Cloudflare 2022, Google 2019, GBIF, Supabase, Zanzibar). The full register is in `references/evidence.md`. Two claims could not be verified against the primary text during research and are marked as such throughout (Nigeria GAID Art. 33 wording; PCI DSS 10.2.2/10.5.1 text). Regime summaries are a design aid, not legal advice.

Evidence is current as at **18 August 2026**. Standards status, regulator guidance and product lifecycles change; re-check anything you intend to quote.

## Contributing

Rules live in `scripts/engine.js` (the `recommend()` function) and are mirrored in `references/decision-rules.md` and `assets/decision-matrix.xlsx`; a change to a rule should touch all three. Every new rule needs a source key in `CITE`. Run `node scripts/recommend.js assets/answers.example.json` after any change and diff the output.

## License

MIT.
