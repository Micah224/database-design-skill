-- =====================================================================
--  EVERYONE IN THE DATABASE — REFERENCE SCHEMA
--  Users → staff / departments / branches → administrators → break-glass
--
--  Target: PostgreSQL 16+ (runs unchanged on 17 and 18).
--  Written for 16 compatibility on purpose:
--    · EXCLUDE USING GIST + btree_gist        (PG18: WITHOUT OVERLAPS / PERIOD)
--    · gen_random_uuid()                       (PG18: uuidv7())
--  Comments mark where the newer syntax applies.
--
--  Apply to an EMPTY database:
--    createdb refschema && psql -d refschema -v ON_ERROR_STOP=1 -f reference-schema.sql
--  Then prove it:
--    psql -d refschema -f schema-tests.sql
--
--  Do not adopt this wholesale. Take the parts your questionnaire
--  checklist names and delete the rest; unused tables still have to be
--  migrated and explained.
-- =====================================================================


-- =====================================================================
-- PART 0 — EXTENSIONS, SCHEMAS, ROLES
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_uuid(), digest()
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- equality inside EXCLUDE constraints
CREATE EXTENSION IF NOT EXISTS ltree;        -- materialised paths for the org tree
CREATE EXTENSION IF NOT EXISTS citext;       -- case-insensitive email

CREATE SCHEMA IF NOT EXISTS core;      -- identity, organisation, authorisation
CREATE SCHEMA IF NOT EXISTS privacy;   -- consent, requests, retention, breaches
CREATE SCHEMA IF NOT EXISTS audit;     -- append-only evidence

-- Four roles. The APPLICATION MUST NOT OWN THE TABLES: an owner bypasses
-- row-level security unless FORCE is set, and a superuser bypasses it
-- regardless. Ownership stays with app_owner; the app runs as app_runtime.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_owner')    THEN CREATE ROLE app_owner    NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_runtime')  THEN CREATE ROLE app_runtime  NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_migrator') THEN CREATE ROLE app_migrator NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='audit_reader') THEN CREATE ROLE audit_reader NOLOGIN; END IF;
END $$;

-- Safety valves. A blocked DDL statement must fail fast, not queue behind
-- every query in the system.
ALTER ROLE app_runtime  SET statement_timeout = '30s';
ALTER ROLE app_runtime  SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE app_migrator SET lock_timeout = '2s';

GRANT USAGE ON SCHEMA core, privacy, audit TO app_owner, app_runtime, app_migrator;
-- (app_owner needs schema USAGE: referential-integrity checks run as the table owner.)
GRANT USAGE ON SCHEMA audit TO audit_reader;


-- =====================================================================
-- PART 1 — TENANCY AND THE ORGANISATION TREE
-- =====================================================================
CREATE TABLE core.tenant (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          text NOT NULL UNIQUE,
  name          text NOT NULL,
  status        text NOT NULL DEFAULT 'active'
                CHECK (status IN ('trial','active','suspended','offboarding','deleted')),
  region        text,                     -- residency: a placement attribute, not a legal entity
  placement     text NOT NULL DEFAULT 'shared',   -- shared | dedicated:<cluster>
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Several overlapping hierarchies over the SAME nodes: legal ownership,
-- operational reporting, geography, cost centres. One tree with mixed node
-- types is wrong for all of them.
CREATE TABLE core.hierarchy (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES core.tenant(id),
  key       text NOT NULL,                -- legal | operational | geographic | cost
  purpose   text,
  UNIQUE (tenant_id, key)
);

CREATE TABLE core.org_node (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid REFERENCES core.tenant(id),
  type         text NOT NULL,             -- group | entity | region | branch | dept | team | ward
  code         text NOT NULL,             -- ltree label: [A-Za-z0-9_]
  name         text NOT NULL,
  jurisdiction text,                      -- becomes an authorisation input when it varies
  operating    daterange NOT NULL DEFAULT daterange(CURRENT_DATE, NULL),
  legal_path   ltree,                     -- materialised path in the LEGAL hierarchy, kept by trigger
  UNIQUE (tenant_id, code),
  CHECK (code ~ '^[A-Za-z0-9_]+$')
);
CREATE INDEX org_node_legal_path_gist ON core.org_node USING GIST (legal_path);

CREATE TABLE core.org_edge (
  hierarchy_id uuid NOT NULL REFERENCES core.hierarchy(id),
  child_id     uuid NOT NULL REFERENCES core.org_node(id),
  parent_id    uuid NOT NULL REFERENCES core.org_node(id),
  valid        tstzrange NOT NULL DEFAULT tstzrange(now(), NULL, '[)'),
  CHECK (child_id <> parent_id),
  -- one parent per hierarchy at any instant; different hierarchies may disagree
  EXCLUDE USING GIST (hierarchy_id WITH =, child_id WITH =, valid WITH &&)
  -- PG18: PRIMARY KEY (hierarchy_id, child_id, valid WITHOUT OVERLAPS)
);

-- Adjacency list is the truth (writes stay simple, FK integrity holds);
-- the materialised path is derived, so reads are one containment test.
CREATE OR REPLACE FUNCTION core.org_node_default_path() RETURNS trigger AS $$
BEGIN
  IF NEW.legal_path IS NULL THEN NEW.legal_path := text2ltree(NEW.code); END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER org_node_default_path BEFORE INSERT ON core.org_node
  FOR EACH ROW EXECUTE FUNCTION core.org_node_default_path();

CREATE OR REPLACE FUNCTION core.org_edge_refresh_path() RETURNS trigger AS $$
DECLARE v_key text; v_parent ltree;
BEGIN
  SELECT key INTO v_key FROM core.hierarchy WHERE id = NEW.hierarchy_id;
  IF v_key <> 'legal' OR NOT (NEW.valid @> now()) THEN RETURN NEW; END IF;
  SELECT legal_path INTO v_parent FROM core.org_node WHERE id = NEW.parent_id;
  -- rewrite the child's path and every descendant's path beneath it
  WITH RECURSIVE sub AS (
    SELECT n.id, v_parent || text2ltree(n.code) AS p FROM core.org_node n WHERE n.id = NEW.child_id
    UNION ALL
    SELECT n.id, s.p || text2ltree(n.code)
      FROM sub s
      JOIN core.org_edge e ON e.parent_id = s.id AND e.hierarchy_id = NEW.hierarchy_id AND e.valid @> now()
      JOIN core.org_node n ON n.id = e.child_id
  )
  UPDATE core.org_node n SET legal_path = sub.p FROM sub WHERE n.id = sub.id;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER org_edge_refresh_path AFTER INSERT OR UPDATE ON core.org_edge
  FOR EACH ROW EXECUTE FUNCTION core.org_edge_refresh_path();


-- =====================================================================
-- PART 2 — IDENTITY
-- =====================================================================
-- ONE table of actors. Customers, staff, contractors, service accounts and
-- the machines that call your API. What differs is the grants they hold,
-- not the table they live in. Separate users/admins/staff tables make
-- every cross-cutting question a UNION and the audit trail polymorphic.
CREATE TABLE core.principal (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid REFERENCES core.tenant(id),
  kind           text NOT NULL DEFAULT 'person' CHECK (kind IN ('person','service','system')),
  -- Status is a state machine, not a boolean. Six states, six behaviours.
  status         text NOT NULL DEFAULT 'pending_verification'
                 CHECK (status IN ('pending_verification','active','locked','suspended','deprovisioned','anonymised')),
  status_reason  text,
  status_changed_by uuid,
  status_changed_at timestamptz,
  email          citext,                  -- nullable: SSO-only principals have none
  email_verified_at timestamptz,
  phone_e164     text CHECK (phone_e164 IS NULL OR phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  phone_verified_at timestamptz,
  username       citext,
  display_name   text,
  legal_name     text,                    -- separable from display_name on purpose
  ial            smallint NOT NULL DEFAULT 1 CHECK (ial BETWEEN 0 AND 3),   -- identity proofing achieved
  ial_achieved_at timestamptz,
  verification_tier text,                 -- KYC tier; limits keyed off it, never role names
  locale         text, timezone text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  deprovisioned_at timestamptz,           -- the trigger…
  access_removed_at timestamptz,          -- …and the effect. The gap is the metric that predicts incidents.
  anonymised_at  timestamptz
);
-- A closed account must not reserve its address forever: uniqueness is
-- scoped to live accounts, so a returning customer can register again.
CREATE UNIQUE INDEX principal_email_live_uq ON core.principal (email)
  WHERE email IS NOT NULL AND status <> 'anonymised';
CREATE UNIQUE INDEX principal_phone_live_uq ON core.principal (phone_e164)
  WHERE phone_e164 IS NOT NULL AND status <> 'anonymised';
CREATE UNIQUE INDEX principal_username_live_uq ON core.principal (tenant_id, username)
  WHERE username IS NOT NULL AND status <> 'anonymised';
CREATE INDEX principal_tenant_idx ON core.principal (tenant_id);

-- Federated identities. Join on (issuer, subject) — NEVER on email, which is
-- mutable, reassignable, and not verified by every issuer.
CREATE TABLE core.identity_link (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,
  issuer       text NOT NULL,             -- OIDC iss / SAML entityID
  subject      text NOT NULL,             -- OIDC sub / SAML NameID
  fal          smallint CHECK (fal BETWEEN 1 AND 3),
  scim_external_id text,                  -- caseExact, unique per provisioning client
  email_at_link citext,                   -- display attribute, not a key
  linked_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz,
  UNIQUE (issuer, subject)
);

-- Authenticators are ROWS, not columns. Users hold several at once; the
-- types need different fields; and the failure counter is scoped to a
-- specific authenticator on an account (NIST 800-63B-4: ≤100 consecutive).
CREATE TABLE core.authenticator (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id       uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,
  type               text NOT NULL CHECK (type IN ('password','passkey','totp','push','sms','smartcard','backup_codes')),
  label              text,
  -- password
  password_hash      text,                -- argon2id / scrypt, self-describing string
  password_changed_at timestamptz,
  breach_checked_at  timestamptz,
  -- WebAuthn credential record (Level 2/3)
  cred_id            bytea,               -- up to 1023 bytes: bytea, NOT uuid
  public_key         bytea,               -- COSE
  sign_count         bigint NOT NULL DEFAULT 0,
  aaguid             uuid,
  transports         text[],
  uv_initialized     boolean,
  backup_eligible    boolean,             -- IMMUTABLE for the credential's life
  backup_state       boolean,             -- mutable
  key_exportable     boolean,             -- NULL = n/a; true ⇒ capped at AAL2
  attestation_fmt    text,
  -- TOTP / push / sms
  secret_enc         bytea,
  totp_last_step     bigint,              -- replay protection
  push_device_id     uuid,
  phone_e164         text,
  -- lifecycle
  consecutive_failed_attempts int NOT NULL DEFAULT 0,   -- per row. Not per account.
  disabled_at        timestamptz,
  last_used_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now()
);
-- Usernameless (discoverable credential) login looks up by credential id alone.
CREATE UNIQUE INDEX authenticator_cred_uq ON core.authenticator (cred_id) WHERE cred_id IS NOT NULL;
CREATE INDEX authenticator_principal_idx ON core.authenticator (principal_id);

CREATE TABLE core.recovery_code (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,
  code_hash    text NOT NULL,             -- hashed like a password
  issued_at    timestamptz NOT NULL DEFAULT now(),
  used_at      timestamptz
);

-- Sessions. AAL is a property of the SESSION (derived from which
-- authenticators were actually presented), never of the account.
-- NIST 800-63B-4 reauth ceilings: AAL1 ≤30 days; AAL2 ≤24h absolute and
-- ≤1h idle (SHOULD); AAL3 SHALL ≤12h absolute and SHOULD ≤15min idle.
CREATE TABLE core.session (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id     uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,
  aal              smallint NOT NULL CHECK (aal BETWEEN 1 AND 3),
  uv_satisfied     boolean NOT NULL DEFAULT false,
  uv_satisfied_at  timestamptz,           -- drives step-up: "strongly authenticated NOW?"
  authenticator_id uuid REFERENCES core.authenticator(id),
  oidc_sid         text,                  -- back-channel logout finds the session by this
  dpop_jkt         text,                  -- sender-constrained tokens
  ip               inet,
  user_agent       text,
  device_id        uuid,
  created_at       timestamptz NOT NULL DEFAULT now(),
  last_seen_at     timestamptz NOT NULL DEFAULT now(),
  absolute_expiry  timestamptz NOT NULL,
  revoked_at       timestamptz,
  revoked_reason   text
);
CREATE INDEX session_principal_live_idx ON core.session (principal_id) WHERE revoked_at IS NULL;
CREATE INDEX session_oidc_sid_idx ON core.session (oidc_sid) WHERE oidc_sid IS NOT NULL;

-- Refresh-token rotation with reuse detection: a token used twice
-- invalidates the whole family.
CREATE TABLE core.refresh_token (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   uuid NOT NULL REFERENCES core.session(id) ON DELETE CASCADE,
  family_id    uuid NOT NULL,
  parent_id    uuid REFERENCES core.refresh_token(id),
  token_hash   text NOT NULL UNIQUE,
  issued_at    timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  used_at      timestamptz,
  revoked_at   timestamptz
);

-- The contact address IS the recovery path. Changing it means proving the
-- NEW value first; the old one stays authoritative until then.
CREATE TABLE core.pending_contact_change (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,
  field        text NOT NULL CHECK (field IN ('email','phone_e164')),
  new_value    text NOT NULL,
  token_hash   text NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  confirmed_at timestamptz
);

-- An invitation is its OWN object. Not a principal in a pending state —
-- that occupies the unique email index, inflates seat counts, and makes
-- cancelling an invitation mean deleting a person.
CREATE TABLE core.invitation (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid REFERENCES core.tenant(id),
  email         citext NOT NULL,
  role_id       uuid,                     -- FK added after core.role exists
  scope_node_id uuid REFERENCES core.org_node(id),
  token_hash    text NOT NULL UNIQUE,     -- single use, bound to this address
  invited_by    uuid NOT NULL REFERENCES core.principal(id),
  expires_at    timestamptz NOT NULL,
  accepted_at   timestamptz,
  accepted_principal_id uuid REFERENCES core.principal(id),
  revoked_at    timestamptz
);


-- =====================================================================
-- PART 3 — AUTHORISATION
-- =====================================================================
-- The permission registry: two columns (action × resource_type), because
-- the permission space in ANSI/INCITS 359 is 2^(OPS × OBS) — generated,
-- not enumerated. Never a string enum in application code.
CREATE TABLE core.permission (
  key                  text PRIMARY KEY,           -- 'refund.approve'
  action               text NOT NULL,
  resource_type        text NOT NULL,
  description          text NOT NULL,              -- shown in the role editor
  is_dangerous         boolean NOT NULL DEFAULT false,
  applies_to_container boolean NOT NULL DEFAULT true,   -- may it be granted at a leaf?
  UNIQUE (action, resource_type)
);

-- Roles are DATA. tenant_id NULL = a system role we ship. A custom role
-- records the base it derives from, so shipped roles can be improved and
-- every derived role inherits the improvement.
CREATE TABLE core.role (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid REFERENCES core.tenant(id),
  key           text NOT NULL,
  name          text NOT NULL,
  description   text,
  is_system     boolean NOT NULL DEFAULT false,
  base_role_id  uuid REFERENCES core.role(id),     -- custom = base + delta
  max_grantable uuid REFERENCES core.role(id),     -- grant ceiling (see also role_grantable)
  min_aal       smallint NOT NULL DEFAULT 1 CHECK (min_aal BETWEEN 1 AND 3),
  requires_issuer text,                            -- hybrid login policy: force SSO for this role
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX role_tenant_key_uq ON core.role (COALESCE(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid), key);

CREATE TABLE core.role_permission (
  role_id        uuid NOT NULL REFERENCES core.role(id) ON DELETE CASCADE,
  permission_key text NOT NULL REFERENCES core.permission(key),
  conditions     jsonb,                            -- {"max_amount": 500} — conditions as data
  PRIMARY KEY (role_id, permission_key)
);

-- Base-plus-delta for custom roles: what was added and what was removed
-- relative to base_role_id. Rendered at read time.
CREATE TABLE core.role_delta (
  role_id        uuid NOT NULL REFERENCES core.role(id) ON DELETE CASCADE,
  permission_key text NOT NULL REFERENCES core.permission(key),
  op             text NOT NULL CHECK (op IN ('add','remove')),
  PRIMARY KEY (role_id, permission_key)
);

-- Role inheritance (senior contains junior). A different axis from
-- organisational inheritance; do not conflate the two.
CREATE TABLE core.role_hierarchy (
  parent_role_id uuid NOT NULL REFERENCES core.role(id) ON DELETE CASCADE,
  child_role_id  uuid NOT NULL REFERENCES core.role(id) ON DELETE CASCADE,
  PRIMARY KEY (parent_role_id, child_role_id),
  CHECK (parent_role_id <> child_role_id)
);

-- Explicit grantable sets: which roles may this role grant?
CREATE TABLE core.role_grantable (
  granter_role_id uuid NOT NULL REFERENCES core.role(id) ON DELETE CASCADE,
  grantee_role_id uuid NOT NULL REFERENCES core.role(id) ON DELETE CASCADE,
  PRIMARY KEY (granter_role_id, grantee_role_id)
);

-- THE GRANT IS THE UNIT OF PRIVILEGE. Not (person, role) — a row that says
-- who, which role, WHERE, whether it flows down the tree, whether it is
-- live or merely eligible, UNTIL WHEN, and who decided.
CREATE TABLE core.role_assignment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid REFERENCES core.tenant(id),
  principal_id    uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,
  role_id         uuid NOT NULL REFERENCES core.role(id),
  scope_node_id   uuid REFERENCES core.org_node(id),      -- NULL = tenant-wide
  inheritable     boolean NOT NULL DEFAULT true,          -- flows to descendants?
  assignment_type text NOT NULL DEFAULT 'active' CHECK (assignment_type IN ('active','eligible')),
  requires_mfa    boolean NOT NULL DEFAULT false,
  requires_justification boolean NOT NULL DEFAULT false,
  valid           tstzrange NOT NULL DEFAULT tstzrange(now(), NULL, '[)'),
  granted_by      uuid REFERENCES core.principal(id),
  granted_at      timestamptz NOT NULL DEFAULT now(),
  justification   text,
  approval_id     uuid,                                   -- FK added after approvals exist
  sponsor_id      uuid REFERENCES core.principal(id),     -- contractors: who vouches
  revoked_at      timestamptz,
  revoked_by      uuid REFERENCES core.principal(id),
  revoked_reason  text,
  -- the same live grant must not exist twice
  EXCLUDE USING GIST (
    principal_id WITH =, role_id WITH =,
    COALESCE(scope_node_id,'00000000-0000-0000-0000-000000000000'::uuid) WITH =,
    valid WITH &&)
  -- PG18: UNIQUE (principal_id, role_id, scope_key, valid WITHOUT OVERLAPS)
);
CREATE INDEX role_assignment_principal_idx ON core.role_assignment (principal_id) WHERE revoked_at IS NULL;
CREATE INDEX role_assignment_scope_idx ON core.role_assignment (scope_node_id);
ALTER TABLE core.invitation ADD CONSTRAINT invitation_role_fk FOREIGN KEY (role_id) REFERENCES core.role(id);

-- Eligible ≠ assigned (INCITS 359: assigned vs activated roles). Just-in-time
-- privilege: hold the dangerous role eligible, activate it deliberately,
-- with a reason and a window, and log the activation itself.
CREATE TABLE core.role_activation (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES core.role_assignment(id) ON DELETE CASCADE,
  session_id    uuid REFERENCES core.session(id),
  reason        text NOT NULL,
  approval_id   uuid,
  "window"      tstzrange NOT NULL,
  activated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX role_activation_assignment_idx ON core.role_activation (assignment_id);

-- Denies: a SEPARATE, last-evaluated layer. The RBAC model is purely
-- additive; deny always wins here and order never matters (cf. Cedar
-- forbid-overrides-permit; XACML's eight combining algorithms are the
-- cautionary tale about ordered rules).
CREATE TABLE core.deny_rule (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid REFERENCES core.tenant(id),
  principal_id   uuid REFERENCES core.principal(id) ON DELETE CASCADE,
  permission_key text REFERENCES core.permission(key),
  resource_type  text,
  resource_id    uuid,
  reason         text NOT NULL,           -- a deny with no reason is unreviewable
  valid          tstzrange NOT NULL DEFAULT tstzrange(now(), NULL, '[)'),
  created_by     uuid REFERENCES core.principal(id)
);

-- Separation of duties as DATA you can query, not a policy document.
-- kind 'static': never both roles.  'dynamic': never both active in one session.
CREATE TABLE core.sod_constraint (
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES core.tenant(id),
  name    text NOT NULL,
  kind    text NOT NULL DEFAULT 'static' CHECK (kind IN ('static','dynamic')),
  rationale text
);
CREATE TABLE core.sod_constraint_role (
  constraint_id uuid NOT NULL REFERENCES core.sod_constraint(id) ON DELETE CASCADE,
  role_id       uuid NOT NULL REFERENCES core.role(id) ON DELETE CASCADE,
  PRIMARY KEY (constraint_id, role_id)
);
CREATE TABLE core.sod_exception (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  constraint_id uuid NOT NULL REFERENCES core.sod_constraint(id) ON DELETE CASCADE,
  principal_id  uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,
  approved_by   uuid NOT NULL REFERENCES core.principal(id),
  reason        text NOT NULL,
  valid         tstzrange NOT NULL
);

-- Delegation vs impersonation. RFC 8693 draws the line precisely:
--   Impersonation: A is "indistinguishable from B in that context".
--   Delegation:    A "still has its own identity separate from B".
-- Build DELEGATION. Auth0's impersonation endpoint survives only under its
-- legacy Authentication API path and is absent from the current product
-- surface — i.e. it was not carried forward. Impersonation makes your audit
-- trail lie; delegation keeps it true.
CREATE TABLE core.delegation (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid REFERENCES core.tenant(id),
  delegator_id   uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,   -- whose authority
  delegate_id    uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,   -- who acts
  capacity       text NOT NULL,           -- cover | agent | guardian | poa | carer
  scope_node_id  uuid REFERENCES core.org_node(id),
  permission_keys text[],                 -- NULL = everything the delegator holds
  evidence_ref   text,                    -- instrument, ticket, signed form
  valid          tstzrange NOT NULL,
  created_by     uuid NOT NULL REFERENCES core.principal(id),
  CHECK (delegator_id <> delegate_id)
);

-- Impersonation, if you must: reason, hard expiry, dual logging, and a
-- notification the subject cannot switch off (the GitHub Enterprise Server
-- ceremony). Every action taken inside it links back here.
CREATE TABLE core.impersonation_session (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid REFERENCES core.tenant(id),
  actor_id      uuid NOT NULL REFERENCES core.principal(id),   -- support agent
  subject_id    uuid NOT NULL REFERENCES core.principal(id),   -- impersonated user
  mode          text NOT NULL DEFAULT 'read_only' CHECK (mode IN ('read_only','full')),
  reason        text NOT NULL,
  approval_id   uuid,
  subject_consented_at timestamptz,
  started_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  ended_at      timestamptz,
  subject_notified_at timestamptz,
  CHECK (actor_id <> subject_id),
  CHECK (expires_at <= started_at + interval '1 hour')
);


-- =====================================================================
-- PART 4 — STAFF, EMPLOYMENT AND ASSIGNMENT
-- =====================================================================
-- EMPLOYMENT (who pays you) ≠ ASSIGNMENT (where you work). Agency nurse on a
-- ward; consultant on a client project; manager over three branches;
-- teacher across two schools. Ed-Fi/OneRoster model exactly this split.
CREATE TABLE core.staff (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid REFERENCES core.tenant(id),
  principal_id  uuid NOT NULL UNIQUE REFERENCES core.principal(id) ON DELETE CASCADE,
  staff_number  text,
  job_title     text,
  job_code      text,                     -- attribute-derived baseline roles key off this
  grade         text,
  UNIQUE (tenant_id, staff_number)
);

CREATE TABLE core.staff_employment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id        uuid NOT NULL REFERENCES core.staff(id) ON DELETE CASCADE,
  employer_id     uuid NOT NULL REFERENCES core.org_node(id),   -- a legal entity node
  employment_type text NOT NULL CHECK (employment_type IN ('employee','contractor','agency','volunteer','partner')),
  jurisdiction    text,
  valid           tstzrange NOT NULL,
  -- a person has at most one employment with a given employer at a time
  EXCLUDE USING GIST (staff_id WITH =, employer_id WITH =, valid WITH &&)
);

CREATE TABLE core.staff_assignment (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id      uuid NOT NULL REFERENCES core.staff(id) ON DELETE CASCADE,
  node_id       uuid NOT NULL REFERENCES core.org_node(id),
  hierarchy_id  uuid NOT NULL REFERENCES core.hierarchy(id),
  relation      text NOT NULL CHECK (relation IN ('primary_base','works_at','manages','covers')),
  valid         tstzrange NOT NULL,
  -- exactly one primary base at any instant: a partial exclusion constraint,
  -- not an is_primary boolean (two booleans can both be true)
  EXCLUDE USING GIST (staff_id WITH =, valid WITH &&) WHERE (relation = 'primary_base'),
  -- and at most one management assignment per hierarchy at a time
  EXCLUDE USING GIST (staff_id WITH =, hierarchy_id WITH =, valid WITH &&) WHERE (relation = 'manages')
);
CREATE INDEX staff_assignment_node_idx ON core.staff_assignment (node_id);

-- Licence/certification with its OWN expiry, separate from the account
-- (49 CFR 395.22 pattern: anchor to the licence; never make it the username).
CREATE TABLE core.staff_credential (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id    uuid NOT NULL REFERENCES core.staff(id) ON DELETE CASCADE,
  kind        text NOT NULL,              -- driving_licence | nursing_reg | teaching_cert
  number_hash text NOT NULL,              -- hash for duplicate detection; the number itself only if a regulator requires it
  issuer      text,
  valid       daterange NOT NULL,
  verified_at timestamptz
);


-- =====================================================================
-- PART 5 — CONSENT AND PRIVACY
-- =====================================================================
-- GDPR Art. 7(1): the controller SHALL be able to DEMONSTRATE consent.
-- A boolean demonstrates nothing. Consent is an append-only event log tied
-- to the exact notice version shown; current state is a VIEW.
CREATE TABLE privacy.notice (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid REFERENCES core.tenant(id),
  key            text NOT NULL,           -- marketing_email | data_sharing | cookies
  version        int  NOT NULL,
  locale         text NOT NULL DEFAULT 'en',
  body           text NOT NULL,
  body_sha256    bytea NOT NULL,
  effective_from timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, key, version, locale)
);

-- Purpose registry with lawful basis and a retention period: the table
-- that makes retention executable instead of aspirational.
CREATE TABLE privacy.purpose (
  key              text PRIMARY KEY,
  description      text NOT NULL,
  lawful_basis     text NOT NULL CHECK (lawful_basis IN ('consent','contract','legal_obligation','vital_interests','public_task','legitimate_interests')),
  retention_class  text NOT NULL CHECK (retention_class IN ('A_discretionary','B_contractual','C_legal_claims','D_audit_pseudonymised','E_erasure_ledger')),
  retention_period interval,
  owner            text NOT NULL
);

CREATE TABLE privacy.consent_event (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid REFERENCES core.tenant(id),
  principal_id     uuid NOT NULL REFERENCES core.principal(id),
  purpose_key      text NOT NULL REFERENCES privacy.purpose(key),
  event            text NOT NULL CHECK (event IN ('given','withdrawn','expired')),
  notice_id        uuid NOT NULL REFERENCES privacy.notice(id),
  presented_sha256 bytea NOT NULL,        -- must equal notice.body_sha256 — trigger-checked
  mechanism        text NOT NULL,         -- checkbox | signature | verbal | api | import
  evidence_ref     text,
  source_ip        inet,
  occurred_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX consent_event_principal_idx ON privacy.consent_event (principal_id, purpose_key, occurred_at DESC);

-- The notice cannot be retro-edited to make old consent look better-informed:
-- if the text changes, the version changes, and the hash must match.
CREATE OR REPLACE FUNCTION privacy.consent_verify_hash() RETURNS trigger AS $$
DECLARE v bytea;
BEGIN
  SELECT body_sha256 INTO v FROM privacy.notice WHERE id = NEW.notice_id;
  IF v IS NULL OR v <> NEW.presented_sha256 THEN
    RAISE EXCEPTION 'consent evidence broken: presented_sha256 does not match notice %', NEW.notice_id;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER consent_verify_hash BEFORE INSERT ON privacy.consent_event
  FOR EACH ROW EXECUTE FUNCTION privacy.consent_verify_hash();

CREATE OR REPLACE FUNCTION privacy.consent_append_only() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'privacy.consent_event is append-only (attempted %)', TG_OP; END $$ LANGUAGE plpgsql;
CREATE TRIGGER consent_append_only BEFORE UPDATE OR DELETE ON privacy.consent_event
  FOR EACH ROW EXECUTE FUNCTION privacy.consent_append_only();

CREATE VIEW privacy.consent_current AS
SELECT DISTINCT ON (principal_id, purpose_key) *
  FROM privacy.consent_event
 ORDER BY principal_id, purpose_key, occurred_at DESC;

-- Acting for someone else: a DATED relationship with capacity, scope and
-- evidence. Never a flag — and never a shared password, which is what users
-- do when you don't build this. (FHIR RelatedPerson + Consent.period.)
CREATE TABLE privacy.proxy_access (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id    uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,   -- the data subject
  proxy_id      uuid NOT NULL REFERENCES core.principal(id) ON DELETE CASCADE,   -- who acts
  capacity      text NOT NULL CHECK (capacity IN ('parent','guardian','carer','next_of_kin','poa','deputy','agent')),
  scope         text[],                   -- data categories, or NULL = all
  evidence_ref  text,
  granted_by    uuid REFERENCES core.principal(id),
  valid         tstzrange NOT NULL,       -- guardian access lapses at an age threshold: put the date here
  CHECK (subject_id <> proxy_id)
);

-- Subject requests, tracked against their statutory deadline.
CREATE TABLE privacy.subject_request (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid REFERENCES core.tenant(id),
  principal_id  uuid REFERENCES core.principal(id) ON DELETE SET NULL,
  kind          text NOT NULL CHECK (kind IN ('access','portability','erasure','rectification','restriction','objection')),
  regime        text NOT NULL,            -- gdpr | ndpa | kenya | popia | ccpa | hipaa
  received_at   timestamptz NOT NULL DEFAULT now(),
  deadline_at   timestamptz NOT NULL,
  identity_verified_at timestamptz,
  state         text NOT NULL DEFAULT 'received' CHECK (state IN ('received','verifying','in_progress','fulfilled','refused','extended')),
  outcome_note  text,
  fulfilled_at  timestamptz
);

-- Class E: the tombstone proves an erasure happened, with NOTHING that
-- re-identifies the subject. Without it the only evidence is absence.
CREATE TABLE privacy.erasure_tombstone (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      uuid REFERENCES privacy.subject_request(id),
  subject_ref_hash bytea NOT NULL,        -- HMAC of the old principal id, keyed; not reversible
  erased_at       timestamptz NOT NULL DEFAULT now(),
  method          text NOT NULL CHECK (method IN ('anonymise','delete','crypto_shred')),
  classes_deleted text[] NOT NULL,
  classes_retained text[] NOT NULL,       -- and why: legal_obligation etc.
  retained_reason text
);

-- Retention drivers per table. Tag or partition every table by class so
-- expiry is a scheduled job, not a judgement call at request time.
CREATE TABLE privacy.retention_policy (
  table_name       text PRIMARY KEY,
  retention_class  text NOT NULL CHECK (retention_class IN ('A_discretionary','B_contractual','C_legal_claims','D_audit_pseudonymised','E_erasure_ledger')),
  retention_period interval,
  clock_column     text NOT NULL,         -- the timestamp the rule is written against
  on_erasure       text NOT NULL CHECK (on_erasure IN ('delete','anonymise','retain','pseudonymise')),
  authority        text                   -- the statute or contract clause
);

-- Breaches carry PER-REGIME deadlines and a MANDATORY rationale for every
-- notification made or withheld. You cannot run every regime to the
-- slowest clock. The clock starts at becoming aware, not at discovery.
CREATE TABLE privacy.breach (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid REFERENCES core.tenant(id),
  discovered_at   timestamptz NOT NULL,
  became_aware_at timestamptz NOT NULL,
  description     text NOT NULL,
  risk_assessment text NOT NULL,
  affected_count  int,
  data_classes    text[]
);
CREATE TABLE privacy.breach_notification (
  breach_id          uuid NOT NULL REFERENCES privacy.breach(id) ON DELETE CASCADE,
  regime             text NOT NULL,       -- gdpr | ndpa | kenya | popia | hipaa | ccpa
  audience           text NOT NULL CHECK (audience IN ('authority','subject')),
  deadline_at        timestamptz NOT NULL,   -- computed per regime; see decision-matrix "Regime clocks"
  notified_at        timestamptz,
  decision_rationale text NOT NULL,      -- why notified — or why not — written AT THE TIME
  PRIMARY KEY (breach_id, regime, audience)
);


-- =====================================================================
-- PART 6 — AUDIT
-- =====================================================================
-- Two logs, two questions. audit.event answers "who approved this and
-- why" (intent, written IN THE SAME TRANSACTION). audit.row_change answers
-- "what changed in this table at 03:00" (values, by trigger, sees writes
-- that bypass the application).
--
-- PCI DSS 10.2.2 mandates: user id, event type, date/time, success/failure,
-- origination, identity of affected data/component/resource. Columns, not
-- free text. Plus the additions that answer real investigations.
CREATE TABLE audit.event (
  id                 uuid NOT NULL DEFAULT gen_random_uuid(),
  occurred_at        timestamptz NOT NULL DEFAULT now(),
  tenant_id          uuid,
  actor_id           uuid,                -- whose permissions were used
  on_behalf_of_id    uuid,                -- who was physically at the keyboard (delegation / impersonation)
  impersonation_session_id uuid,
  session_id         uuid,
  session_aal        smallint,            -- "was this done under MFA?" — answerable years later
  action             text NOT NULL,       -- a permission key, not prose
  resource_type      text,
  resource_id        uuid,
  outcome            text NOT NULL CHECK (outcome IN ('allowed','denied','error')),
  via_assignment_id  uuid,                -- which grant permitted it
  approval_id        uuid,
  source_ip          inet,
  user_agent         text,
  request_id         text,                -- the join to application logs
  detail             jsonb,
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
-- Partition on the timestamp your RETENTION RULE is written against.
-- Expiry becomes DETACH + DROP, a metadata operation, not a mass DELETE.
CREATE TABLE audit.event_default PARTITION OF audit.event DEFAULT;
CREATE TABLE audit.event_2026_09 PARTITION OF audit.event FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE audit.event_2026_10 PARTITION OF audit.event FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE INDEX audit_event_actor_idx    ON audit.event (actor_id, occurred_at DESC);
CREATE INDEX audit_event_resource_idx ON audit.event (resource_type, resource_id, occurred_at DESC);
CREATE INDEX audit_event_tenant_idx   ON audit.event (tenant_id, occurred_at DESC);

-- Append-only to the APPLICATION. This does NOT constrain an owner or a
-- superuser: "the owner implicitly has all grant options for the object"
-- (PostgreSQL docs, GRANT). The control that constrains people is a copy
-- shipped off-box under different credentials (NIST 800-53 AU-9(2)).
CREATE OR REPLACE FUNCTION audit.append_only() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'audit.event is append-only (attempted %)', TG_OP; END $$ LANGUAGE plpgsql;
CREATE TRIGGER audit_event_append_only BEFORE UPDATE OR DELETE ON audit.event
  FOR EACH ROW EXECUTE FUNCTION audit.append_only();
REVOKE ALL ON audit.event FROM app_runtime;
GRANT INSERT ON audit.event TO app_runtime;
GRANT SELECT ON audit.event TO audit_reader;

-- Row-change log. NOTE: there is currently no maintained generic row-audit
-- extension for PostgreSQL (supa_audit archived Feb 2025; pgMemento last
-- release Oct 2022; 2ndQuadrant audit-trigger: "PRs are not accepted").
-- So: a delta, not row images; partitioned; attached to the tables that
-- matter (grants, money, config), not everywhere.
CREATE TABLE audit.row_change (
  id             uuid NOT NULL DEFAULT gen_random_uuid(),
  occurred_at    timestamptz NOT NULL DEFAULT clock_timestamp(),  -- wall-clock of the statement
  txn_started_at timestamptz NOT NULL DEFAULT now(),              -- transaction start
  stmt_started_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  txid           bigint NOT NULL DEFAULT txid_current(),
  relid          oid NOT NULL,            -- survives table renames
  table_name     text NOT NULL,
  op             text NOT NULL CHECK (op IN ('INSERT','UPDATE','DELETE')),
  row_pk         text,
  actor_id       uuid,                    -- from app.actor_id if the app sets it
  changed_cols   text[],
  old_delta      jsonb,                   -- only the columns that changed
  new_delta      jsonb,
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE TABLE audit.row_change_default PARTITION OF audit.row_change DEFAULT;
CREATE TABLE audit.row_change_2026_09 PARTITION OF audit.row_change FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE INDEX audit_row_change_rel_idx ON audit.row_change (relid, occurred_at DESC);

CREATE OR REPLACE FUNCTION audit.log_row_change() RETURNS trigger AS $$
DECLARE o jsonb; n jsonb; cols text[]; od jsonb := '{}'; nd jsonb := '{}'; k text; pk text; act uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN n := to_jsonb(NEW); nd := n; cols := ARRAY(SELECT jsonb_object_keys(n));
  ELSIF TG_OP = 'DELETE' THEN o := to_jsonb(OLD); od := o; cols := ARRAY(SELECT jsonb_object_keys(o));
  ELSE
    o := to_jsonb(OLD); n := to_jsonb(NEW); cols := ARRAY[]::text[];
    FOR k IN SELECT jsonb_object_keys(n) LOOP
      IF (o -> k) IS DISTINCT FROM (n -> k) THEN
        cols := cols || k; od := od || jsonb_build_object(k, o -> k); nd := nd || jsonb_build_object(k, n -> k);
      END IF;
    END LOOP;
    IF cols = ARRAY[]::text[] THEN RETURN NULL; END IF;   -- no-op update: nothing to record
  END IF;
  pk := COALESCE(n ->> 'id', o ->> 'id');
  BEGIN act := NULLIF(current_setting('app.actor_id', true), '')::uuid; EXCEPTION WHEN OTHERS THEN act := NULL; END;
  INSERT INTO audit.row_change (relid, table_name, op, row_pk, actor_id, changed_cols, old_delta, new_delta)
  VALUES (TG_RELID, TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP, pk, act, cols, od, nd);
  RETURN NULL;
END $$ LANGUAGE plpgsql;

-- Attach to the tables where forensic coverage matters.
CREATE TRIGGER role_assignment_row_change AFTER INSERT OR UPDATE OR DELETE ON core.role_assignment
  FOR EACH ROW EXECUTE FUNCTION audit.log_row_change();
CREATE TRIGGER role_permission_row_change AFTER INSERT OR UPDATE OR DELETE ON core.role_permission
  FOR EACH ROW EXECUTE FUNCTION audit.log_row_change();
CREATE TRIGGER deny_rule_row_change AFTER INSERT OR UPDATE OR DELETE ON core.deny_rule
  FOR EACH ROW EXECUTE FUNCTION audit.log_row_change();

-- A revoked grant must remain visible as a historical fact. Deleting the row
-- destroys the only evidence that the access ever existed. Where hard
-- deletes are unavoidable, keep the last image here.
CREATE TABLE audit.deleted_record (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deleted_at  timestamptz NOT NULL DEFAULT now(),
  table_name  text NOT NULL,
  row_pk      text NOT NULL,
  deleted_by  uuid,
  reason      text,
  last_image  jsonb NOT NULL
);


-- =====================================================================
-- PART 7 — APPROVALS (MAKER–CHECKER / DUAL CONTROL)
-- =====================================================================
-- The approval is its OWN object, bound to a hash of exactly what was
-- approved. Four rules, each the subject of a real incident somewhere:
--   1. approver ≠ maker                       (CHECK constraint, not app logic)
--   2. payload hash at decision = at request  (rebind on change)
--   3. the request has not expired
--   4. the decision was not made inside an impersonation session
CREATE TABLE core.approval_request (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid REFERENCES core.tenant(id),
  action_key         text NOT NULL,       -- role.grant | payout.change | data.export | breakglass.activate
  payload            jsonb NOT NULL,
  payload_sha256     bytea NOT NULL,
  maker_id           uuid NOT NULL REFERENCES core.principal(id),
  justification      text NOT NULL,
  state              text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','approved','rejected','expired','cancelled','executed')),
  required_approvals smallint NOT NULL DEFAULT 1 CHECK (required_approvals >= 1),
  created_at         timestamptz NOT NULL DEFAULT now(),
  expires_at         timestamptz NOT NULL,
  executed_at        timestamptz
);
ALTER TABLE core.role_assignment  ADD CONSTRAINT role_assignment_approval_fk  FOREIGN KEY (approval_id) REFERENCES core.approval_request(id);
ALTER TABLE core.role_activation  ADD CONSTRAINT role_activation_approval_fk  FOREIGN KEY (approval_id) REFERENCES core.approval_request(id);
ALTER TABLE core.impersonation_session ADD CONSTRAINT impersonation_approval_fk FOREIGN KEY (approval_id) REFERENCES core.approval_request(id);

-- Rebind: any change to the payload invalidates the approval already given.
CREATE OR REPLACE FUNCTION core.approval_request_rebind() RETURNS trigger AS $$
BEGIN
  IF NEW.payload IS DISTINCT FROM OLD.payload THEN
    NEW.payload_sha256 := digest(NEW.payload::text, 'sha256');
    IF OLD.state = 'approved' THEN NEW.state := 'pending'; END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER approval_request_rebind BEFORE UPDATE ON core.approval_request
  FOR EACH ROW EXECUTE FUNCTION core.approval_request_rebind();

CREATE TABLE core.approval_decision (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      uuid NOT NULL REFERENCES core.approval_request(id) ON DELETE CASCADE,
  approver_id     uuid NOT NULL REFERENCES core.principal(id),
  maker_id        uuid NOT NULL,          -- denormalised by trigger so the CHECK can see it
  decision        text NOT NULL CHECK (decision IN ('approve','reject')),
  approved_sha256 bytea NOT NULL,         -- must match the request at decision time
  impersonation_session_id uuid REFERENCES core.impersonation_session(id),
  note            text,
  decided_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT no_self_approval CHECK (approver_id <> maker_id),
  UNIQUE (request_id, approver_id)
);

CREATE OR REPLACE FUNCTION core.approval_guard() RETURNS trigger AS $$
DECLARE r core.approval_request%ROWTYPE; n_ok int;
BEGIN
  SELECT * INTO r FROM core.approval_request WHERE id = NEW.request_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'approval request % not found', NEW.request_id; END IF;
  NEW.maker_id := r.maker_id;                                   -- feeds the CHECK constraint
  IF r.state NOT IN ('pending') THEN
    RAISE EXCEPTION 'approval request % is %, not pending', r.id, r.state;
  END IF;
  IF r.expires_at <= now() THEN
    UPDATE core.approval_request SET state = 'expired' WHERE id = r.id;
    RAISE EXCEPTION 'approval request % expired at %', r.id, r.expires_at;
  END IF;
  IF NEW.approved_sha256 <> r.payload_sha256 THEN
    RAISE EXCEPTION 'approval is bound to payload %, request now has % (payload changed after review)',
      encode(NEW.approved_sha256,'hex'), encode(r.payload_sha256,'hex');
  END IF;
  IF NEW.impersonation_session_id IS NOT NULL THEN
    RAISE EXCEPTION 'a decision cannot be made from inside an impersonation session';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER approval_guard BEFORE INSERT ON core.approval_decision
  FOR EACH ROW EXECUTE FUNCTION core.approval_guard();

-- Promote the request once enough distinct approvers have approved.
CREATE OR REPLACE FUNCTION core.approval_tally() RETURNS trigger AS $$
DECLARE r core.approval_request%ROWTYPE; n int;
BEGIN
  SELECT * INTO r FROM core.approval_request WHERE id = NEW.request_id;
  IF NEW.decision = 'reject' THEN
    UPDATE core.approval_request SET state = 'rejected' WHERE id = r.id;
  ELSE
    SELECT count(*) INTO n FROM core.approval_decision WHERE request_id = r.id AND decision = 'approve';
    IF n >= r.required_approvals THEN UPDATE core.approval_request SET state = 'approved' WHERE id = r.id; END IF;
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER approval_tally AFTER INSERT ON core.approval_decision
  FOR EACH ROW EXECUTE FUNCTION core.approval_tally();


-- =====================================================================
-- PART 8 — ACCESS REVIEW (RECERTIFICATION EVIDENCE)
-- =====================================================================
-- A campaign SNAPSHOTS what was under review. Reading live tables means
-- the attestation describes something that may no longer exist. Include
-- last_used_at: a reviewer shown "unused for 11 months" revokes; one shown
-- only a role name approves everything.
CREATE TABLE core.access_review_campaign (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid REFERENCES core.tenant(id),
  name        text NOT NULL,
  trigger     text NOT NULL CHECK (trigger IN ('scheduled','transfer','role_change','incident','breakglass')),
  scope_node_id uuid REFERENCES core.org_node(id),
  opened_at   timestamptz NOT NULL DEFAULT now(),
  due_at      timestamptz NOT NULL,
  closed_at   timestamptz,
  opened_by   uuid NOT NULL REFERENCES core.principal(id)
);
CREATE TABLE core.access_review_item (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id         uuid NOT NULL REFERENCES core.access_review_campaign(id) ON DELETE CASCADE,
  assignment_id       uuid REFERENCES core.role_assignment(id),
  -- snapshot columns: what it looked like AT REVIEW TIME
  snap_principal_name text NOT NULL,
  snap_role_name      text NOT NULL,
  snap_scope_name     text,
  snap_granted_at     timestamptz,
  snap_granted_by     text,
  snap_last_used_at   timestamptz,
  reviewer_id         uuid REFERENCES core.principal(id),
  decision            text CHECK (decision IN ('keep','revoke','modify')),
  decision_note       text,
  decided_at          timestamptz
);
CREATE TABLE core.access_review_attestation (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id  uuid NOT NULL REFERENCES core.access_review_campaign(id) ON DELETE CASCADE,
  attester_id  uuid NOT NULL REFERENCES core.principal(id),
  statement    text NOT NULL,
  items_reviewed int NOT NULL,
  attested_at  timestamptz NOT NULL DEFAULT now()
);


-- =====================================================================
-- PART 9 — EFFECTIVE PERMISSIONS
-- =====================================================================
-- ONE function, used by every call site. Two code paths that compute
-- permissions differently will disagree, and the disagreement is a
-- vulnerability. Resolves: live assignments → activation for eligible
-- grants → role-hierarchy closure → scope inheritance (ltree) → denies.
CREATE OR REPLACE FUNCTION core.effective_permissions(
  p_principal uuid, p_scope uuid DEFAULT NULL, p_at timestamptz DEFAULT now())
RETURNS TABLE (permission_key text, via_assignment_id uuid) AS $$
  WITH RECURSIVE live AS (
    SELECT ra.id, ra.role_id, ra.scope_node_id, ra.inheritable
      FROM core.role_assignment ra
     WHERE ra.principal_id = p_principal
       AND ra.valid @> p_at
       AND (ra.revoked_at IS NULL OR ra.revoked_at > p_at)
       AND (ra.assignment_type = 'active'
            OR EXISTS (SELECT 1 FROM core.role_activation act
                        WHERE act.assignment_id = ra.id AND act."window" @> p_at))
  ), in_scope AS (
    SELECT l.*
      FROM live l
     WHERE l.scope_node_id IS NULL
        OR p_scope IS NULL AND FALSE          -- no scope asked: only tenant-wide grants apply
        OR l.scope_node_id = p_scope
        OR (l.inheritable AND EXISTS (
              SELECT 1 FROM core.org_node s, core.org_node t
               WHERE s.id = l.scope_node_id AND t.id = p_scope
                 AND s.legal_path @> t.legal_path))
  ), closure AS (
    SELECT i.id AS assignment_id, i.role_id FROM in_scope i
    UNION
    SELECT c.assignment_id, rh.child_role_id
      FROM closure c JOIN core.role_hierarchy rh ON rh.parent_role_id = c.role_id
  )
  SELECT DISTINCT rp.permission_key, c.assignment_id
    FROM closure c
    JOIN core.role_permission rp ON rp.role_id = c.role_id
   WHERE NOT EXISTS (
           SELECT 1 FROM core.deny_rule d
            WHERE d.principal_id = p_principal
              AND (d.permission_key IS NULL OR d.permission_key = rp.permission_key)
              AND d.valid @> p_at)
$$ LANGUAGE sql STABLE;

-- Cached permission sets need a version stamp so a revocation invalidates
-- them (and offline clients know how stale they are).
CREATE TABLE core.tenant_permissions_version (
  tenant_id uuid PRIMARY KEY,            -- zero-uuid row = system roles
  version   bigint NOT NULL DEFAULT 1,
  bumped_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION core.bump_permissions_version() RETURNS trigger AS $$
DECLARE t uuid; j jsonb;
BEGIN
  j := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  t := COALESCE(
         (j ->> 'tenant_id')::uuid,
         (SELECT r.tenant_id FROM core.role r WHERE r.id = (j ->> 'role_id')::uuid),
         '00000000-0000-0000-0000-000000000000'::uuid);
  INSERT INTO core.tenant_permissions_version (tenant_id) VALUES (t)
  ON CONFLICT (tenant_id) DO UPDATE SET version = core.tenant_permissions_version.version + 1, bumped_at = now();
  RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER role_assignment_bump AFTER INSERT OR UPDATE OR DELETE ON core.role_assignment
  FOR EACH ROW EXECUTE FUNCTION core.bump_permissions_version();
CREATE TRIGGER role_permission_bump AFTER INSERT OR UPDATE OR DELETE ON core.role_permission
  FOR EACH ROW EXECUTE FUNCTION core.bump_permissions_version();
CREATE TRIGGER deny_rule_bump AFTER INSERT OR UPDATE OR DELETE ON core.deny_rule
  FOR EACH ROW EXECUTE FUNCTION core.bump_permissions_version();

-- Grant ceiling: an administrator may only grant what they hold (or what
-- their role explicitly lists as grantable). Enforced HERE, the only place
-- a second code path cannot bypass.
CREATE OR REPLACE FUNCTION core.enforce_grant_ceiling() RETURNS trigger AS $$
DECLARE ok boolean;
BEGIN
  IF NEW.granted_by IS NULL THEN RETURN NEW; END IF;                    -- system provisioning
  IF current_setting('app.bypass_grant_ceiling', true) = 'on' THEN RETURN NEW; END IF;   -- seeding/migration only
  SELECT EXISTS (
    SELECT 1 FROM core.role_assignment g
      JOIN core.role_grantable rg ON rg.granter_role_id = g.role_id
     WHERE g.principal_id = NEW.granted_by AND g.valid @> now() AND g.revoked_at IS NULL
       AND rg.grantee_role_id = NEW.role_id
  ) OR NOT EXISTS (SELECT 1 FROM core.role_permission rp WHERE rp.role_id = NEW.role_id
                    AND rp.permission_key NOT IN (SELECT permission_key FROM core.effective_permissions(NEW.granted_by, NEW.scope_node_id)))
  INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'grant ceiling: % may not grant role % (not held, not listed as grantable)', NEW.granted_by, NEW.role_id; END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER role_assignment_ceiling BEFORE INSERT ON core.role_assignment
  FOR EACH ROW EXECUTE FUNCTION core.enforce_grant_ceiling();

-- Static separation of duties, checked AT GRANT TIME.
CREATE OR REPLACE FUNCTION core.enforce_sod() RETURNS trigger AS $$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT sc.id, sc.name
      FROM core.sod_constraint sc
      JOIN core.sod_constraint_role a ON a.constraint_id = sc.id AND a.role_id = NEW.role_id
      JOIN core.sod_constraint_role b ON b.constraint_id = sc.id AND b.role_id <> NEW.role_id
      JOIN core.role_assignment rb ON rb.role_id = b.role_id AND rb.principal_id = NEW.principal_id
                                  AND rb.valid && NEW.valid AND rb.revoked_at IS NULL
     WHERE sc.kind = 'static'
       AND NOT EXISTS (SELECT 1 FROM core.sod_exception e
                        WHERE e.constraint_id = sc.id AND e.principal_id = NEW.principal_id AND e.valid @> now())
  LOOP
    IF current_setting('app.sod_mode', true) = 'warn' THEN
      RAISE WARNING 'separation of duties: "%" would be breached by this grant', c.name;
    ELSE
      RAISE EXCEPTION 'separation of duties: "%" forbids holding this role alongside an existing one (record an exception first)', c.name;
    END IF;
  END LOOP;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER role_assignment_sod BEFORE INSERT ON core.role_assignment
  FOR EACH ROW EXECUTE FUNCTION core.enforce_sod();

-- Live SoD conflicts, as a query you can schedule.
CREATE VIEW core.sod_conflicts AS
SELECT DISTINCT ra.principal_id, sc.id AS constraint_id, sc.name AS conflict
  FROM core.sod_constraint sc
  JOIN core.sod_constraint_role a ON a.constraint_id = sc.id
  JOIN core.sod_constraint_role b ON b.constraint_id = sc.id AND b.role_id <> a.role_id
  JOIN core.role_assignment ra ON ra.role_id = a.role_id AND ra.valid @> now() AND ra.revoked_at IS NULL
  JOIN core.role_assignment rb ON rb.role_id = b.role_id AND rb.valid @> now() AND rb.revoked_at IS NULL
                              AND rb.principal_id = ra.principal_id
 WHERE NOT EXISTS (SELECT 1 FROM core.sod_exception e
                    WHERE e.constraint_id = sc.id AND e.principal_id = ra.principal_id AND e.valid @> now());


-- =====================================================================
-- PART 10 — ROW LEVEL SECURITY (TENANT ISOLATION BACKSTOP)
-- =====================================================================
-- A backstop against application bugs, not a substitute for scoping
-- queries. Three things people get wrong:
--   · owners bypass RLS unless FORCE is set; superusers always bypass it
--   · referential-integrity checks ALWAYS bypass RLS (documented covert channel)
--   · PERMISSIVE policies OR together; use RESTRICTIVE for isolation so a
--     later policy cannot widen it
-- Write the call as (SELECT core.current_tenant()) so the planner hoists it
-- into an InitPlan: Supabase's published benchmark measured ~178,000 ms → ~12 ms.
CREATE OR REPLACE FUNCTION core.current_tenant() RETURNS uuid AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION core.current_scope_nodes() RETURNS SETOF uuid AS $$
  SELECT unnest(string_to_array(NULLIF(current_setting('app.scope_nodes', true), ''), ','))::uuid
$$ LANGUAGE sql STABLE;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['core.principal','core.org_node','core.role_assignment','core.staff','core.approval_request','privacy.consent_event'] LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %s AS RESTRICTIVE
                     USING (tenant_id IS NULL OR tenant_id = (SELECT core.current_tenant()))
                     WITH CHECK (tenant_id IS NULL OR tenant_id = (SELECT core.current_tenant()))$p$, t);
    -- a permissive policy must also exist or nothing is visible at all
    EXECUTE format('CREATE POLICY app_access ON %s FOR ALL TO app_runtime USING (true) WITH CHECK (true)', t);
  END LOOP;
END $$;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA core    TO app_runtime;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA privacy TO app_runtime;
GRANT INSERT ON audit.row_change TO app_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO audit_reader;
-- Ownership belongs to app_owner, never to app_runtime.
-- VIEWS: a view runs with its OWNER's privileges by default, so a view owned
-- by a superuser silently bypasses every row-level-security policy on the
-- tables beneath it. security_invoker (PG15+) makes the view run as the
-- caller; owning it as app_owner removes the superuser bypass either way.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ('core','privacy','audit') LOOP
    EXECUTE format('ALTER TABLE %I.%I OWNER TO app_owner', r.schemaname, r.tablename);
  END LOOP;
  FOR r IN SELECT schemaname, viewname FROM pg_views WHERE schemaname IN ('core','privacy','audit') LOOP
    EXECUTE format('ALTER VIEW %I.%I OWNER TO app_owner', r.schemaname, r.viewname);
    EXECUTE format('ALTER VIEW %I.%I SET (security_invoker = true)', r.schemaname, r.viewname);
  END LOOP;
END $$;
GRANT SELECT ON privacy.consent_current, core.sod_conflicts TO app_runtime;


-- =====================================================================
-- PART 11 — SEED DATA
-- =====================================================================
INSERT INTO core.hierarchy (tenant_id, key, purpose) VALUES
  (NULL, 'legal',       'Legal ownership: group → entity → branch'),
  (NULL, 'operational', 'Reporting lines: division → department → team'),
  (NULL, 'geographic',  'Region → country → site'),
  (NULL, 'cost',        'Cost centres')
ON CONFLICT DO NOTHING;

INSERT INTO core.permission (key, action, resource_type, description, is_dangerous) VALUES
  ('user.read',            'read',    'user',       'View user records',                  false),
  ('user.create',          'create',  'user',       'Create user accounts',               false),
  ('user.suspend',         'suspend', 'user',       'Suspend a user account',             true),
  ('user.impersonate',     'impersonate','user',    'Act on behalf of a user',            true),
  ('role.read',            'read',    'role',       'View roles and assignments',         false),
  ('role.grant',           'grant',   'role',       'Assign a role to a principal',       true),
  ('role.define',          'define',  'role',       'Create or edit custom roles',        true),
  ('org.read',             'read',    'org_node',   'View the organisation tree',         false),
  ('org.manage',           'manage',  'org_node',   'Create, rename or close org nodes',  true),
  ('staff.read',           'read',    'staff',      'View staff records',                 false),
  ('staff.assign',         'assign',  'staff',      'Assign staff to branches/departments', false),
  ('audit.read',           'read',    'audit',      'Read the security audit log',        true),
  ('consent.read',         'read',    'consent',    'View consent records',               false),
  ('privacy.fulfil_request','fulfil', 'subject_request','Fulfil a data subject request',  true),
  ('approval.approve',     'approve', 'approval',   'Approve a pending request',          true),
  ('billing.read',         'read',    'billing',    'View billing information',           false),
  ('billing.manage',       'manage',  'billing',    'Change payment methods and plans',   true),
  ('security.manage',      'manage',  'security',   'Manage security settings and policy',true)
ON CONFLICT DO NOTHING;

-- System roles. Note the deliberate separation of BILLING and SECURITY from
-- general administration — every mature product examined (GitHub, Slack,
-- Notion, Stripe) does this, and outsiders never do.
DO $seed$
DECLARE v_viewer uuid; v_member uuid; v_admin uuid; v_billing uuid; v_security uuid; v_iam uuid; v_bg uuid;
BEGIN
  INSERT INTO core.role (id, tenant_id, key, name, is_system, min_aal, description) VALUES
    (gen_random_uuid(), NULL, 'viewer',   'Viewer',   true, 1, 'Read-only across granted scopes'),
    (gen_random_uuid(), NULL, 'member',   'Member',   true, 1, 'Ordinary authenticated participant; rights come from relationships, not this role'),
    (gen_random_uuid(), NULL, 'admin',    'Administrator', true, 2, 'Operational administration, excluding billing and security'),
    (gen_random_uuid(), NULL, 'billing_manager','Billing Manager', true, 2, 'Billing only. Cannot see operational data.'),
    (gen_random_uuid(), NULL, 'security_admin','Security Administrator', true, 2, 'Security policy and audit. NIST AC-5: must NOT also administer access.'),
    (gen_random_uuid(), NULL, 'iam_admin','Access Administrator', true, 2, 'Manages access. Cannot grant roles it does not hold, and cannot read the audit log.'),
    (gen_random_uuid(), NULL, 'platform.break_glass','Break Glass', true, 3, 'Emergency access. MUST be time-boxed, justified and approved. A ROLE, never a boolean.')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_viewer   FROM core.role WHERE key='viewer'   AND tenant_id IS NULL;
  SELECT id INTO v_member   FROM core.role WHERE key='member'   AND tenant_id IS NULL;
  SELECT id INTO v_admin    FROM core.role WHERE key='admin'    AND tenant_id IS NULL;
  SELECT id INTO v_billing  FROM core.role WHERE key='billing_manager' AND tenant_id IS NULL;
  SELECT id INTO v_security FROM core.role WHERE key='security_admin'  AND tenant_id IS NULL;
  SELECT id INTO v_iam      FROM core.role WHERE key='iam_admin'       AND tenant_id IS NULL;
  SELECT id INTO v_bg       FROM core.role WHERE key='platform.break_glass' AND tenant_id IS NULL;

  INSERT INTO core.role_permission (role_id, permission_key)
  SELECT v_viewer, k FROM unnest(ARRAY['user.read','role.read','org.read','staff.read']) k
  ON CONFLICT DO NOTHING;

  INSERT INTO core.role_permission (role_id, permission_key)
  SELECT v_admin, k FROM unnest(ARRAY['user.read','user.create','user.suspend',
      'role.read','org.read','org.manage','staff.read','staff.assign',
      'consent.read','approval.approve']) k
  ON CONFLICT DO NOTHING;

  INSERT INTO core.role_permission (role_id, permission_key)
  SELECT v_billing, k FROM unnest(ARRAY['billing.read','billing.manage']) k
  ON CONFLICT DO NOTHING;

  -- NIST SP 800-53 AC-5 discussion, verbatim: "security personnel who
  -- administer access control functions do not also administer audit
  -- functions." Hence security_admin reads the audit log but CANNOT grant
  -- roles, and iam_admin grants roles but CANNOT read the audit log.
  INSERT INTO core.role_permission (role_id, permission_key)
  SELECT v_security, k FROM unnest(ARRAY['audit.read','security.manage','role.read']) k
  ON CONFLICT DO NOTHING;

  INSERT INTO core.role_permission (role_id, permission_key)
  SELECT v_iam, k FROM unnest(ARRAY['role.read','role.grant','role.define','user.read']) k
  ON CONFLICT DO NOTHING;

  -- Break glass holds everything — which is exactly why it is eligible-only.
  INSERT INTO core.role_permission (role_id, permission_key)
  SELECT v_bg, key FROM core.permission ON CONFLICT DO NOTHING;

  -- iam_admin may grant the ordinary roles, never security or break-glass.
  INSERT INTO core.role_grantable (granter_role_id, grantee_role_id)
  SELECT v_iam, r FROM unnest(ARRAY[v_viewer, v_member, v_admin, v_billing]) r
  ON CONFLICT DO NOTHING;

  -- The AC-5 split, as a testable constraint.
  INSERT INTO core.sod_constraint (id, tenant_id, name, kind, rationale) VALUES
    ('11111111-1111-1111-1111-111111111111', NULL, 'access-admin vs audit-admin (NIST AC-5)', 'static',
     'Whoever grants access must not be the person who reviews the audit log.');
  INSERT INTO core.sod_constraint_role (constraint_id, role_id) VALUES
    ('11111111-1111-1111-1111-111111111111', v_iam),
    ('11111111-1111-1111-1111-111111111111', v_security);
END $seed$;

INSERT INTO privacy.purpose (key, description, lawful_basis, retention_class, retention_period, owner) VALUES
  ('service_delivery','Providing the contracted service','contract','B_contractual', interval '7 years','Product'),
  ('marketing_email', 'Sending marketing email','consent','A_discretionary', NULL,'Marketing'),
  ('security_audit',  'Detecting and investigating misuse','legitimate_interests','D_audit_pseudonymised', interval '12 months','Security'),
  ('legal_claims',    'Establishing, exercising or defending legal claims','legitimate_interests','C_legal_claims', interval '6 years','Legal')
ON CONFLICT DO NOTHING;

INSERT INTO privacy.retention_policy (table_name, retention_class, retention_period, clock_column, on_erasure, authority) VALUES
  ('core.principal',          'B_contractual',          interval '7 years',  'deprovisioned_at', 'anonymise',  'accounting/tax retention'),
  ('core.session',            'A_discretionary',        interval '90 days',  'created_at',       'delete',     '—'),
  ('core.role_assignment',    'D_audit_pseudonymised',  interval '7 years',  'revoked_at',       'pseudonymise','access history is audit evidence'),
  ('privacy.consent_event',   'D_audit_pseudonymised',  interval '7 years',  'occurred_at',      'pseudonymise','GDPR Art. 7(1) demonstrability'),
  ('audit.event',             'D_audit_pseudonymised',  interval '12 months','occurred_at',      'pseudonymise','PCI DSS 10.5.1 / 6 years under HIPAA'),
  ('privacy.erasure_tombstone','E_erasure_ledger',      NULL,                'erased_at',        'retain',     'proof the request was honoured')
ON CONFLICT DO NOTHING;


-- =====================================================================
-- PART 12 — THE QUERIES THAT PROVE THE DESIGN WORKS
-- =====================================================================
-- If your schema cannot answer these, it will fail an audit. Keep them as
-- integration tests, not as documentation.

-- Q1. "Who could approve a payment in the Manchester branch on 3 March?"
--     Note EVERY predicate carries the as-at instant.
/*
SELECT DISTINCT p.id, p.display_name
FROM   core.principal p
JOIN   core.role_assignment ra ON ra.principal_id = p.id
JOIN   core.role_permission rp ON rp.role_id = ra.role_id
LEFT JOIN core.org_node n      ON n.id = ra.scope_node_id
WHERE  rp.permission_key = 'approval.approve'
  AND  ra.valid @> TIMESTAMPTZ '2026-03-03'
  AND  (ra.revoked_at IS NULL OR ra.revoked_at > TIMESTAMPTZ '2026-03-03')
  AND  (ra.scope_node_id IS NULL
        OR n.legal_path @> (SELECT legal_path FROM core.org_node WHERE code='MCR'));
*/

-- Q2. "Show every privileged grant made last quarter, with who approved it and why."
/*
SELECT ra.granted_at, p.display_name AS grantee, r.name AS role, n.name AS scope,
       g.display_name AS granted_by, ra.justification, ar.id AS approval, ad.approver_id
FROM   core.role_assignment ra
JOIN   core.role r ON r.id = ra.role_id
JOIN   core.principal p ON p.id = ra.principal_id
LEFT JOIN core.principal g ON g.id = ra.granted_by
LEFT JOIN core.org_node n ON n.id = ra.scope_node_id
LEFT JOIN core.approval_request ar ON ar.id = ra.approval_id
LEFT JOIN core.approval_decision ad ON ad.request_id = ar.id AND ad.decision = 'approve'
WHERE  EXISTS (SELECT 1 FROM core.role_permission rp JOIN core.permission pm ON pm.key = rp.permission_key
                WHERE rp.role_id = ra.role_id AND pm.is_dangerous)
  AND  ra.granted_at >= date_trunc('quarter', now()) - interval '3 months'
  AND  ra.granted_at <  date_trunc('quarter', now());
*/

-- Q3. "List every live separation-of-duties conflict, excluding documented exceptions."
/*  SELECT * FROM core.sod_conflicts;  */

-- Q4. "What did support do while impersonating customers last month?"
/*
SELECT e.occurred_at, a.display_name AS agent, s.display_name AS customer, e.action, e.resource_type, e.resource_id, i.reason
FROM   audit.event e
JOIN   core.impersonation_session i ON i.id = e.impersonation_session_id
JOIN   core.principal a ON a.id = i.actor_id
JOIN   core.principal s ON s.id = i.subject_id
WHERE  e.occurred_at >= date_trunc('month', now()) - interval '1 month'
  AND  e.occurred_at <  date_trunc('month', now());
*/

-- Q5. "Prove this customer consented to marketing on this date, and show the exact wording."
/*
SELECT ce.occurred_at, ce.event, ce.mechanism, n.version, n.body, encode(ce.presented_sha256,'hex') AS hash
FROM   privacy.consent_event ce
JOIN   privacy.notice n ON n.id = ce.notice_id
WHERE  ce.principal_id = $1 AND ce.purpose_key = 'marketing_email'
  AND  ce.occurred_at <= TIMESTAMPTZ '2026-03-03'
ORDER  BY ce.occurred_at DESC LIMIT 1;
*/

-- Q6. "How long, on average, between someone leaving and their access stopping?"
/*
SELECT avg(access_removed_at - deprovisioned_at) AS mean_lag,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY access_removed_at - deprovisioned_at) AS p95_lag
FROM   core.principal
WHERE  deprovisioned_at IS NOT NULL AND access_removed_at IS NOT NULL;
*/
