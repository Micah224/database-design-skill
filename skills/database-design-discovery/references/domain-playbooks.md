# Domain playbooks

The privilege ladder is the same everywhere; what differs is which questions are load-bearing. These are the questions this volume would ask first in each domain, and the answers that survive scrutiny.

## 9.1 Financial services

The domain where the audit trail is the product. Every design decision here is downstream of one fact: money movements are irreversible, so the record of who authorised what must be reconstructible years later.

| Question you must answer | The pattern that holds up |
|---|---|
| How is money represented? | An immutable double-entry ledger, with balances derived and optionally materialised for speed. A mutable balance column cannot be reconciled, cannot answer a dispute, and cannot be reconstructed as at a past date. |
| Who may initiate, and who may approve? | Never the same person for the same transaction. A CHECK constraint on the approval table, not a rule in a runbook. |
| Do limits vary by person, role or customer tier? | They vary by all three in any real system. Limits are authorization attributes stored as data, not constants in configuration. |
| How many verification tiers are there? | Store the tier on the principal and the limits against the tier. Never encode the tier in a role name. |
| How is support scoped? | Refunds, disputes and transfers are separate roles. The mature payment dashboards separate them because the fraud each enables is different. |
| What must reconcile, and against what? | An external source of truth daily at minimum. If nothing external reconciles, the ledger is only internally consistent, which is not the same as correct. |
| How long is the retention? | Typically 7–10 years, jurisdiction-dependent, which makes hard deletion impossible and anonymisation the only lawful erasure route. |

> **THE THREE FINTECH SCHEMA ERRORS THAT RECUR** — **A balance column that is updated in place.** It destroys the evidence of how the balance was reached.
>
> **Storing money as a float.** Use a scaled integer or numeric with an explicit currency column. Every currency has its own minor-unit scale, and several have none.
>
> **A single "support" role.** It is how a support agent ends up able to issue a refund and then close the dispute that would have surfaced it.

## 9.2 B2B SaaS

The domain where the customer, not you, defines the organisational structure — and where the enterprise deal that arrives in month eighteen dictates decisions you should have made in month one.

| Question you must answer | The pattern that holds up |
|---|---|
| Is it multi-tenant, and how isolated? | Shared schema with tenant_id and RESTRICTIVE row-level security by default, plus a placement indirection so a large customer can be moved to a dedicated database without a schema change. |
| How large is the largest tenant relative to the median? | If the answer is 100× or more, plan tenant-level partitioning before the deal, not during the incident. |
| Do customers define their own roles? | Eventually, yes. Build the permission registry now and the editor later. Custom roles as base plus delta, private to the tenant. |
| Do customers bring their own identity provider? | Enterprise buyers require SAML or OIDC plus SCIM. Join on (issuer, subject); deprovisioning arrives as active:false, not as a delete. |
| Is there a guest class? | Yes, and one person is a guest in several tenants at once. One identity, several memberships — not several accounts. |
| Who administers what? | The four-part pattern: container hierarchy, grade ladder, orthogonal functional admins (billing, security), and a guest class. |
| How do tenants export and leave? | Self-service export, and a documented deletion path with a certificate. It is asked in the first enterprise security review. |

> **THE ENTERPRISE CHECKLIST ARRIVES WHETHER YOU ARE READY OR NOT** — SAML and SCIM, audit log export, session policy, IP allow-listing, data residency, sub-processor list, deletion certificate, and role customisation. Every item is cheap if the schema anticipated it and expensive if it did not. The tenant-level configuration table that holds all of this should exist from the first release, even if it holds two rows.

## 9.3 Healthcare

The domain where role alone never answers the question. The same nurse may legitimately see one patient and not another, and what separates the two cases is a current care relationship rather than a job title.

| Question you must answer | The pattern that holds up |
|---|---|
| How is clinical access decided? | Professional role, plus an active care relationship, plus location, plus a period. The clinical interoperability standards model exactly this combination as a single dated relationship, because none of the four alone is sufficient. |
| Is there emergency override? | Break-glass with a recorded reason, immediate alerting and mandatory post-hoc review. Access is granted, then justified, then examined — never silently granted. |
| How granular is patient consent to sharing? | Per data category, per recipient, with a validity period. A single share flag cannot express the cases that actually arise. |
| Do patients have proxies? | Carers, next of kin, and legally appointed representatives — each a dated relationship with its own evidence and its own scope. |
| Are reads audited? | Yes, and this is the expensive requirement. Log at query-intent level and alert on access without a care relationship, which is the row that matters. |
| How long is the retention? | Documentation retained six years under the federal rule, and often far longer under national clinical-records rules. Design for cold storage from the start. |

> **THE PATIENT-FACING ACCESS LOG** — Letting patients see who viewed their record is the strongest single deterrent to inappropriate access, and it costs one screen over data you are already required to collect. It also converts the audit log from a compliance artefact into a product feature, which is the only reliable way to keep it accurate.

## 9.4 Commerce and point of sale

The domain where a physical shop floor breaks the assumptions of a web session, and where inventory is a ledger pretending to be a number.

| Question you must answer | The pattern that holds up |
|---|---|
| Is stock tracked per location? | Once there is more than one location, stock is a per-location movement ledger and the on-hand figure is derived. A quantity column across locations cannot represent a transfer in flight. |
| Do staff share a till? | Then the device session and the human session are separate objects. Authenticate the device durably; authenticate the human per shift or per sensitive action with a fast credential. |
| Are some actions manager-approved rather than allowed or denied? | Yes — and the mature point-of-sale systems model exactly three states: allowed, denied, and requiring approval. A boolean cannot express how a shop actually runs. |
| Is it a marketplace? | Then each seller is effectively a tenant with its own privilege ladder, its own staff and its own custom roles, inside your tenant model. |
| Are card numbers in scope? | Almost never should they be. Hosted fields or tokenisation keeps the number out of your environment and is the largest single scope reduction available. |
| What survives a customer deletion request? | The order and its tax records; not the identity attached to them. Separate the customer record from the transaction record so one can be severed from the other. |

## 9.5 Logistics and field operations

The domain where the licence, not the account, is the thing that expires — and where connectivity is a design assumption rather than a given.

| Question you must answer | The pattern that holds up |
|---|---|
| Is the work governed by a licence or certification? | Then the credential is a separate object from the identity, with its own expiry, and an expired credential must block assignment automatically rather than raise a report. |
| What identifies the worker? | Anchor the record to the licence; issue a separate account identifier. The federal rule for electronic driver logs requires exactly this separation. |
| Do they work offline? | Cache the permission set with a version stamp and a maximum staleness, and require an online re-check before genuinely dangerous actions. |
| Is there high-frequency telemetry? | Positions and sensor readings are a separate storage problem from your entity data. Partition by time; do not put them in the same table as the work orders. |
| Is access rostered? | Usually soft rather than hard — log and review out-of-hours access rather than blocking it, because the emergency call-out is exactly when the system must work. |

## 9.6 Education

The domain where everything is dated, and where the guardian relationship has a built-in expiry that most schemas miss.

| Question you must answer | The pattern that holds up |
|---|---|
| Is access bounded by academic periods? | Yes. Enrolment is a dated association; a teacher's access to last year's class is a different fact from their access this year, and both must be representable. |
| Who employs, and who assigns? | Frequently different organisations — a trust employs, a school assigns. The education data standards model these as separate dated associations for exactly this reason. |
| Do guardians have access? | Yes, and it lapses at an age threshold. A dated relationship with an automatic end, not a permanent link. |
| Who moderates assessment? | Not the person who taught the cohort. A separation-of-duties pair, enforced at grant time. |
| What is the lawful basis for children's data? | Usually the institution's, not the learner's consent — which changes the consent model entirely and should be recorded as such. |

## 9.7 Government and public sector

The domain where the retention schedule is published, the access rules are statutory, and "we deleted it" can itself be an offence.

| Question you must answer | The pattern that holds up |
|---|---|
| Is there a statutory retention and disposal schedule? | Then retention is not a policy you choose. Encode the schedule as data, with the disposal action and the authority for it, and make disposal an audited event. |
| Are records subject to freedom-of-information requests? | Then a publication classification belongs on the record itself, decided when it is created rather than when it is requested. |
| How is access decided? | Frequently clearance plus need-to-know plus role — three independent dimensions that the federal control catalogue treats separately, and that must not be collapsed into one. |
| Must decisions about a person be explainable to them? | Yes. Record the decision, the reason and the rule applied, not just the outcome. Administrative-law expectations become schema columns. |
| Is there an archival transfer obligation? | Then some records leave your system permanently and the transfer itself is a record. Model the handover, not just the deletion. |
