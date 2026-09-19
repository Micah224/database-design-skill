# Design principles: the shape of the problem

Before any of the tiers, four structural decisions. Each of them is cheap now and painful later, and each of them is routinely got wrong in a way that is invisible for the first year.

## 1.1 One table of people, not four

The most common opening move in a new system is to create a `users` table, and then — when staff appear — an `admins` table, and then, when the customer's own employees appear, a `staff` table. It feels tidy. It is the decision that makes everything downstream harder.

The moment there are two tables of people, every cross-cutting question needs a UNION. *Who signed in yesterday?* Union. *Who has an unverified email?* Union. *Who did this?* — and now the audit table needs either two nullable foreign keys or a polymorphic `actor_type` column that no constraint can check. Worse, the same human being routinely appears in more than one of the tables: the shop owner who is also a customer, the doctor who is also a patient, the employee who buys from their own company. With separate tables they are separate people, which is wrong, and the wrongness surfaces as duplicated identity, split history, and a subject-access request you cannot answer completely.

The pattern that holds up is one **principal** table containing every actor — customers, employees, contractors, service accounts, and the machine identities that call your API. What differentiates them is not the table they live in but the grants they hold and the profile rows that hang off them. A person who is both a customer and an employee is one principal with two sets of grants, and every question about them has a single answer.

This is not a novel idea. It is the party/role pattern from the data-modelling literature: a *party* is a person or an organisation, and every role that party plays is a separate, dated relationship rather than a column on the party. The reason it keeps being rediscovered is that the alternative fails in exactly the same way every time.

```sql
-- One table. Kind is a discriminator, not a separate table.
CREATE TABLE core.principal (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid REFERENCES core.tenant(id),
  kind          text NOT NULL CHECK (kind IN ('person','service','system')),
  status        text NOT NULL,          -- see 1.2
  email         citext,                 -- nullable: SSO-only principals have none
  display_name  text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- A closed account must not reserve its address forever.
CREATE UNIQUE INDEX principal_email_live_uq ON core.principal (email)
  WHERE email IS NOT NULL AND status <> 'anonymised';
```

> **THE TELL** — If your audit table has an `actor_type` column, or two nullable actor foreign keys, or a comment explaining which one to read — you have separate people tables and the audit trail is already paying for it.

## 1.2 Status is a state machine, not a boolean

`is_active` is the second-cheapest mistake in this volume. It collapses at least six distinct situations into one bit, and every one of them needs different behaviour:

| State | What it means | Can they sign in? | Do you keep their data? |
|---|---|---|---|
| pending_verification | Registered, contact not yet proven | No | Yes, briefly — then expire |
| active | Normal | Yes | Yes |
| locked | Automatic, from failed attempts or risk signals | No, until unlocked | Yes |
| suspended | Deliberate, by an administrator, for a reason | No | Yes |
| deprovisioned | Left the organisation; access removed | No | Yes — history is still needed |
| anonymised | Erasure honoured; identifiers destroyed | No, permanently | Only what law requires |

The differences matter operationally. A *locked* account unlocks itself on a timer or after recovery; a *suspended* one requires a human decision and should carry the reason and the person who made it. A *deprovisioned* account must still be joinable from historical records, or last year's approvals become anonymous. An *anonymised* one must stop blocking the unique index on email, or a customer who exercised their right to erasure can never come back — a genuinely common and genuinely embarrassing bug.

Note also that suspension is not the same as removing someone's roles. Stripping roles destroys the record of what they had; suspension preserves it. When they return from leave, or when the investigation clears them, you want to restore rather than reconstruct.

## 1.3 The grant is the unit of privilege

Most systems store privilege as a link between a person and a role. That shape answers *what may this person do* and nothing else. The questions that actually get asked in production are:

- *Where* may they do it — everywhere, or only at their branch, or only at their branch and the ones beneath it?
- *Until when* — is this permanent, or cover for someone on leave until Friday?
- *Who decided* — who granted this, on what approval, and for what stated reason?
- *Is it live now, or merely available* — some rights should be held in an eligible state and activated deliberately, with the activation itself logged.
So the unit is not a pair. It is a row that looks roughly like this, and getting to this shape early is the single highest-leverage decision in the whole volume:

```sql
CREATE TABLE core.role_assignment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id    uuid NOT NULL REFERENCES core.principal(id),
  role_id         uuid NOT NULL REFERENCES core.role(id),
  scope_node_id   uuid REFERENCES core.org_node(id),   -- NULL = tenant-wide
  inheritable     boolean NOT NULL DEFAULT true,       -- does it flow down the tree?
  assignment_type text NOT NULL DEFAULT 'active'       -- 'active' | 'eligible'
                  CHECK (assignment_type IN ('active','eligible')),
  valid           tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  granted_by      uuid REFERENCES core.principal(id),
  justification   text,
  approval_id     uuid REFERENCES core.approval_request(id),
  -- the same live grant must not exist twice
  EXCLUDE USING GIST (principal_id WITH =, role_id WITH =,
    COALESCE(scope_node_id, '00...0'::uuid) WITH =, valid WITH &&)
);
```

Six extra columns. They are the difference between a system that can answer an auditor and one that cannot, and between "the regional manager can see her region" being a query and being a special case in application code.

## 1.4 Ten decisions that are expensive to reverse

Everything in this volume is reversible with effort. These ten are the ones where the effort is measured in quarters rather than days, because they either touch every table or destroy information you did not record.

| # | Decision | Why reversing it is expensive |
|---|---|---|
| 1 | Whether the system is multi-tenant | Adding a tenant column later means touching every table, index, query and cached decision — and auditing every one for the case you missed. |
| 2 | One people table or several | Merging them retrospectively means reconciling duplicate humans and rewriting every audit reference. |
| 3 | Whether assignments carry a validity period | History you did not record does not exist. No amount of later work recovers it. |
| 4 | Whether permissions are data or code | Retrofitting a permission registry means finding and rewriting every authorization call site. |
| 5 | Whether a permission can be scoped to a unit | Adding scope later means re-deriving what every existing global grant should have been scoped to — and nobody remembers. |
| 6 | Whether consent is an event log or a flag | You cannot reconstruct what wording a user saw in 2024 from a boolean set to true. |
| 7 | What the login handle is | Changing it means a migration that touches every user, every integration and every support script. |
| 8 | Whether the audit trail is written in the same transaction | A gap-ridden historical log cannot be repaired, only annotated. |
| 9 | Whether identity is joined on (issuer, subject) or on email | Joining on email silently merges different people; unpicking it means manual review of every collision. |
| 10 | Whether the org structure is one tree or several | Splitting a conflated tree means re-deciding, for every node, which hierarchy it belonged to. |

> **THE PATTERN IN THAT LIST** — Eight of the ten are about **recording something you were not recording**, not about choosing the wrong technology. Migrations move data; they cannot invent it. That asymmetry is why this volume spends more time on what to store than on what to store it in.
