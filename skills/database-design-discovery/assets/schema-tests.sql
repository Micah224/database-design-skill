-- Run:  createdb reftest && psql -d reftest -v ON_ERROR_STOP=1 -f reference-schema.sql
--       psql -d reftest -f schema-tests.sql
-- The whole run happens inside one transaction that is ROLLED BACK at the end,
-- so it can be re-run on the same database as often as you like.
-- Functional tests: prove the constraints actually enforce what they claim.
-- Constraints you have not tried to violate are constraints you are assuming.
\set ON_ERROR_STOP off
\pset pager off

CREATE OR REPLACE FUNCTION t(label text, ok boolean) RETURNS void AS $$
BEGIN RAISE NOTICE '%  %', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, label; END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION must_fail(label text, stmt text) RETURNS void AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'FAIL  % (statement unexpectedly succeeded)', label;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  % (rejected: %)', label, left(SQLERRM, 70);
  END;
END $$ LANGUAGE plpgsql;

BEGIN;
-- ---------------------------------------------------------------- fixtures
SET LOCAL app.bypass_grant_ceiling = 'on';   -- seeding; switched off where the ceiling is under test
DO $fx$
DECLARE v_t uuid; v_legal uuid; v_grp uuid; v_ldn uuid; v_mcr uuid; v_ops uuid;
        v_alice uuid; v_bob uuid; v_carol uuid; v_staff uuid; v_admin uuid; v_viewer uuid;
BEGIN
  INSERT INTO core.tenant (id, slug, name) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','acme','Acme Ltd') RETURNING id INTO v_t;
  SELECT id INTO v_legal FROM core.hierarchy WHERE key='legal' AND tenant_id IS NULL;
  SELECT id INTO v_ops   FROM core.hierarchy WHERE key='operational' AND tenant_id IS NULL;

  INSERT INTO core.org_node (id, tenant_id, type, code, name) VALUES
    ('bbbbbbbb-0000-0000-0000-000000000001', v_t, 'group',  'GRP', 'Acme Group'),
    ('bbbbbbbb-0000-0000-0000-000000000002', v_t, 'branch', 'LDN', 'London'),
    ('bbbbbbbb-0000-0000-0000-000000000003', v_t, 'branch', 'MCR', 'Manchester');
  v_grp := 'bbbbbbbb-0000-0000-0000-000000000001'; v_ldn := 'bbbbbbbb-0000-0000-0000-000000000002'; v_mcr := 'bbbbbbbb-0000-0000-0000-000000000003';
  INSERT INTO core.org_edge (hierarchy_id, child_id, parent_id) VALUES (v_legal, v_ldn, v_grp), (v_legal, v_mcr, v_grp);

  INSERT INTO core.principal (id, tenant_id, status, email, display_name) VALUES
    ('cccccccc-0000-0000-0000-000000000001', v_t, 'active', 'alice@acme.example', 'Alice'),
    ('cccccccc-0000-0000-0000-000000000002', v_t, 'active', 'bob@acme.example',   'Bob'),
    ('cccccccc-0000-0000-0000-000000000003', v_t, 'active', 'carol@acme.example', 'Carol');
  v_alice := 'cccccccc-0000-0000-0000-000000000001'; v_bob := 'cccccccc-0000-0000-0000-000000000002'; v_carol := 'cccccccc-0000-0000-0000-000000000003';

  INSERT INTO core.staff (id, tenant_id, principal_id, staff_number) VALUES ('dddddddd-0000-0000-0000-000000000001', v_t, v_alice, 'S001');
  INSERT INTO core.staff_employment (staff_id, employer_id, employment_type, valid)
    VALUES ('dddddddd-0000-0000-0000-000000000001', v_grp, 'employee', tstzrange('2024-01-01', NULL, '[)'));
  -- Alice was based in London Jan–Jun 2025, then Manchester.
  INSERT INTO core.staff_assignment (staff_id, node_id, hierarchy_id, relation, valid) VALUES
    ('dddddddd-0000-0000-0000-000000000001', v_ldn, v_legal, 'primary_base', tstzrange('2025-01-01','2025-07-01','[)')),
    ('dddddddd-0000-0000-0000-000000000001', v_mcr, v_legal, 'primary_base', tstzrange('2025-07-01', NULL, '[)'));
END $fx$;

-- ============================================================ 1
\echo === 1. Effective permissions: inheritance down the org tree ===
DO $$
DECLARE v_admin uuid; v_alice uuid := 'cccccccc-0000-0000-0000-000000000001';
        v_grp uuid := 'bbbbbbbb-0000-0000-0000-000000000001'; v_mcr uuid := 'bbbbbbbb-0000-0000-0000-000000000003'; v_ldn uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
        v_bob uuid := 'cccccccc-0000-0000-0000-000000000002';
BEGIN
  SELECT id INTO v_admin FROM core.role WHERE key='admin' AND tenant_id IS NULL;
  INSERT INTO core.role_assignment (tenant_id, principal_id, role_id, scope_node_id, inheritable)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_alice, v_admin, v_grp, true);
  PERFORM t('inheritable grant at group flows down to branch',
    EXISTS (SELECT 1 FROM core.effective_permissions(v_alice, v_mcr) WHERE permission_key='org.manage'));
  INSERT INTO core.role_assignment (tenant_id, principal_id, role_id, scope_node_id, inheritable)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_bob, v_admin, v_ldn, false);
  PERFORM t('non-inheritable grant at London does NOT reach Manchester',
    NOT EXISTS (SELECT 1 FROM core.effective_permissions(v_bob, v_mcr) WHERE permission_key='org.manage')
    AND EXISTS (SELECT 1 FROM core.effective_permissions(v_bob, v_ldn) WHERE permission_key='org.manage'));
END $$;

-- ============================================================ 2
\echo === 2. Eligible assignments are NOT entitlements until activated ===
DO $$
DECLARE v_bg uuid; v_carol uuid := 'cccccccc-0000-0000-0000-000000000003'; v_ra uuid;
BEGIN
  SELECT id INTO v_bg FROM core.role WHERE key='platform.break_glass' AND tenant_id IS NULL;
  INSERT INTO core.role_assignment (tenant_id, principal_id, role_id, assignment_type, requires_mfa, requires_justification)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_carol, v_bg, 'eligible', true, true) RETURNING id INTO v_ra;
  PERFORM t('eligible-but-inactive grants nothing',
    NOT EXISTS (SELECT 1 FROM core.effective_permissions(v_carol, NULL) WHERE permission_key='audit.read'));
  INSERT INTO core.role_activation (assignment_id, reason, "window")
    VALUES (v_ra, 'INC-4471: restore payouts after outage', tstzrange(now(), now() + interval '30 minutes', '[)'));
  PERFORM t('activated eligible assignment grants the permission',
    EXISTS (SELECT 1 FROM core.effective_permissions(v_carol, NULL) WHERE permission_key='audit.read'));
END $$;

-- ============================================================ 3
\echo === 3. Deny rules take unconditional precedence ===
DO $$
DECLARE v_alice uuid := 'cccccccc-0000-0000-0000-000000000001'; v_mcr uuid := 'bbbbbbbb-0000-0000-0000-000000000003';
BEGIN
  INSERT INTO core.deny_rule (tenant_id, principal_id, permission_key, reason, created_by)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_alice, 'user.suspend', 'conflict of interest: HR case 77', v_alice);
  PERFORM t('deny rule overrides an inherited allow',
    NOT EXISTS (SELECT 1 FROM core.effective_permissions(v_alice, v_mcr) WHERE permission_key='user.suspend')
    AND EXISTS (SELECT 1 FROM core.effective_permissions(v_alice, v_mcr) WHERE permission_key='org.manage'));
END $$;

-- ============================================================ 4
\echo === 4. Temporal constraints on assignments ===
SELECT must_fail('overlapping primary_base assignments rejected',
  $q$INSERT INTO core.staff_assignment (staff_id, node_id, hierarchy_id, relation, valid)
     SELECT 'dddddddd-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', id, 'primary_base', tstzrange('2025-03-01','2025-04-01','[)')
       FROM core.hierarchy WHERE key='legal' AND tenant_id IS NULL$q$);
SELECT must_fail('a node cannot have two parents in one hierarchy at once',
  $q$INSERT INTO core.org_edge (hierarchy_id, child_id, parent_id)
     SELECT id, 'bbbbbbbb-0000-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000002'
       FROM core.hierarchy WHERE key='legal' AND tenant_id IS NULL$q$);
SELECT must_fail('duplicate live role assignment rejected',
  $q$INSERT INTO core.role_assignment (tenant_id, principal_id, role_id, scope_node_id)
     SELECT 'aaaaaaaa-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', id, 'bbbbbbbb-0000-0000-0000-000000000001'
       FROM core.role WHERE key='admin' AND tenant_id IS NULL$q$);

-- ============================================================ 5
\echo === 5. Consent evidence integrity ===
DO $$
DECLARE v_n uuid; v_alice uuid := 'cccccccc-0000-0000-0000-000000000001'; ok boolean;
BEGIN
  INSERT INTO privacy.notice (tenant_id, key, version, body, body_sha256)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'marketing_email', 1, 'We will email you offers.', digest('We will email you offers.','sha256'))
    RETURNING id INTO v_n;
  BEGIN
    INSERT INTO privacy.consent_event (tenant_id, principal_id, purpose_key, event, notice_id, presented_sha256, mechanism)
      VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_alice, 'marketing_email', 'given', v_n, digest('different wording','sha256'), 'checkbox');
    PERFORM t('consent with a mismatched notice hash rejected', false);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  consent with a mismatched notice hash rejected (rejected: %)', left(SQLERRM,70);
  END;
  INSERT INTO privacy.consent_event (tenant_id, principal_id, purpose_key, event, notice_id, presented_sha256, mechanism, occurred_at)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_alice, 'marketing_email', 'given', v_n, digest('We will email you offers.','sha256'), 'checkbox', now() - interval '1 day');
  INSERT INTO privacy.consent_event (tenant_id, principal_id, purpose_key, event, notice_id, presented_sha256, mechanism)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_alice, 'marketing_email', 'withdrawn', v_n, digest('We will email you offers.','sha256'), 'preference_centre');
  SELECT (SELECT count(*) FROM privacy.consent_event WHERE principal_id = v_alice) = 2
     AND (SELECT event FROM privacy.consent_current WHERE principal_id = v_alice AND purpose_key='marketing_email') = 'withdrawn' INTO ok;
  PERFORM t('withdrawal is a new row and the current-state view reflects it', ok);
END $$;

-- ============================================================ 6
\echo === 6. Maker-checker ===
DO $$
DECLARE v_req uuid; v_alice uuid := 'cccccccc-0000-0000-0000-000000000001'; v_bob uuid := 'cccccccc-0000-0000-0000-000000000002'; h bytea;
BEGIN
  INSERT INTO core.approval_request (tenant_id, action_key, payload, payload_sha256, maker_id, justification, expires_at)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'payout.change', '{"iban":"GB00AAAA","amount":500}', digest('{"iban":"GB00AAAA","amount":500}','sha256'), v_alice, 'customer request #88', now() + interval '1 day')
    RETURNING id, payload_sha256 INTO v_req, h;
  BEGIN
    INSERT INTO core.approval_decision (request_id, approver_id, decision, approved_sha256) VALUES (v_req, v_alice, 'approve', h);
    PERFORM t('self-approval blocked', false);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PASS  self-approval blocked (rejected: %)', left(SQLERRM,70); END;
  BEGIN
    INSERT INTO core.approval_decision (request_id, approver_id, decision, approved_sha256) VALUES (v_req, v_bob, 'approve', digest('tampered','sha256'));
    PERFORM t('approval bound to payload hash (tamper blocked)', false);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PASS  approval bound to payload hash (tamper blocked) (rejected: %)', left(SQLERRM,70); END;
  INSERT INTO core.approval_decision (request_id, approver_id, decision, approved_sha256) VALUES (v_req, v_bob, 'approve', h);
  PERFORM t('a different approver on the unchanged payload succeeds',
    (SELECT state FROM core.approval_request WHERE id = v_req) = 'approved');
  -- editing the payload after approval drops it back to pending
  UPDATE core.approval_request SET payload = '{"iban":"GB00BBBB","amount":500}' WHERE id = v_req;
  PERFORM t('editing an approved payload invalidates the approval (rebind)',
    (SELECT state FROM core.approval_request WHERE id = v_req) = 'pending');
END $$;

-- ============================================================ 7
\echo === 7. Audit log is append-only to the application ===
INSERT INTO audit.event (tenant_id, actor_id, action, outcome) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'role.grant', 'allowed');
SELECT must_fail('UPDATE on audit.event rejected', $q$UPDATE audit.event SET outcome='denied'$q$);
SELECT must_fail('DELETE on audit.event rejected', $q$DELETE FROM audit.event$q$);

-- ============================================================ 8
\echo === 8. Row-change log captured the grants automatically ===
DO $$
DECLARE n int; v bigint;
BEGIN
  SELECT count(*) INTO n FROM audit.row_change WHERE table_name='core.role_assignment' AND op='INSERT';
  PERFORM t('trigger captured role_assignment writes', n >= 3);
  SELECT version INTO v FROM core.tenant_permissions_version WHERE tenant_id='aaaaaaaa-0000-0000-0000-000000000001';
  PERFORM t('permissions_version bumped on grant change', v >= 3);
END $$;

-- ============================================================ 9
\echo === 9. Separation of duties (NIST AC-5) ===
DO $$
DECLARE v_iam uuid; v_sec uuid; v_bob uuid := 'cccccccc-0000-0000-0000-000000000002';
BEGIN
  SELECT id INTO v_iam FROM core.role WHERE key='iam_admin' AND tenant_id IS NULL;
  SELECT id INTO v_sec FROM core.role WHERE key='security_admin' AND tenant_id IS NULL;
  INSERT INTO core.role_assignment (tenant_id, principal_id, role_id) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_bob, v_iam);
  BEGIN
    INSERT INTO core.role_assignment (tenant_id, principal_id, role_id) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_bob, v_sec);
    PERFORM t('access-admin + audit-admin conflict blocked at grant time', false);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PASS  access-admin + audit-admin conflict blocked at grant time (rejected: %)', left(SQLERRM,70); END;
  -- with a documented exception, the grant goes through and the conflicts view stays clean
  INSERT INTO core.sod_exception (constraint_id, principal_id, approved_by, reason, valid)
    VALUES ('11111111-1111-1111-1111-111111111111', v_bob, 'cccccccc-0000-0000-0000-000000000003', 'two-person team; compensating review weekly', tstzrange(now(), now() + interval '90 days','[)'));
  INSERT INTO core.role_assignment (tenant_id, principal_id, role_id) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_bob, v_sec);
  PERFORM t('documented exception permits the grant and suppresses the conflict view',
    NOT EXISTS (SELECT 1 FROM core.sod_conflicts WHERE principal_id = v_bob));
  DELETE FROM core.sod_exception WHERE principal_id = v_bob;
  PERFORM t('SoD conflict is detectable once the exception lapses',
    EXISTS (SELECT 1 FROM core.sod_conflicts WHERE principal_id = v_bob));
END $$;

-- ============================================================ 10
\echo === 10. Grant ceiling: an admin may only grant what they hold or may grant ===
SET LOCAL app.bypass_grant_ceiling = 'off';
DO $$
DECLARE v_iam uuid; v_viewer uuid; v_sec uuid; v_bob uuid := 'cccccccc-0000-0000-0000-000000000002'; v_carol uuid := 'cccccccc-0000-0000-0000-000000000003';
BEGIN
  SELECT id INTO v_iam    FROM core.role WHERE key='iam_admin' AND tenant_id IS NULL;
  SELECT id INTO v_viewer FROM core.role WHERE key='viewer' AND tenant_id IS NULL;
  SELECT id INTO v_sec    FROM core.role WHERE key='security_admin' AND tenant_id IS NULL;
  -- Bob holds iam_admin (from test 9); iam_admin lists viewer as grantable
  INSERT INTO core.role_assignment (tenant_id, principal_id, role_id, granted_by, justification)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_carol, v_viewer, v_bob, 'onboarding');
  PERFORM t('iam_admin can grant a role listed as grantable', true);
  BEGIN
    -- Alice holds admin (no audit.read, no security.manage) and nothing grantable: she may not grant security_admin
    INSERT INTO core.role_assignment (tenant_id, principal_id, role_id, granted_by)
      VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_carol, v_sec, 'cccccccc-0000-0000-0000-000000000001');
    PERFORM t('a principal cannot grant a role above their own ceiling', false);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PASS  a principal cannot grant a role above their own ceiling (rejected: %)', left(SQLERRM,70); END;
END $$;
SET LOCAL app.bypass_grant_ceiling = 'on';

-- ============================================================ 11
\echo === 11. Soft-delete does not block re-registration ===
DO $$
DECLARE ok boolean;
BEGIN
  INSERT INTO core.principal (tenant_id, status, email, display_name) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'active', 'dave@acme.example', 'Dave');
  UPDATE core.principal SET status='anonymised', anonymised_at=now(), display_name=NULL WHERE email='dave@acme.example' AND status='active';
  INSERT INTO core.principal (tenant_id, status, email, display_name) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'active', 'dave@acme.example', 'Dave again');
  SELECT count(*) = 2 INTO ok FROM core.principal WHERE email='dave@acme.example';
  PERFORM t('an anonymised account does not block the address forever', ok);
END $$;
SELECT must_fail('but two LIVE accounts on one address are still rejected',
  $q$INSERT INTO core.principal (tenant_id, status, email) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','active','dave@acme.example')$q$);

-- ============================================================ 12
\echo === 12. Point-in-time reconstruction ===
DO $$
DECLARE n text;
BEGIN
  SELECT o.name INTO n FROM core.staff_assignment a JOIN core.org_node o ON o.id = a.node_id
   WHERE a.staff_id='dddddddd-0000-0000-0000-000000000001' AND a.relation='primary_base' AND a.valid @> TIMESTAMPTZ '2025-03-03';
  PERFORM t('"where was this person based on 3 March 2025" is answerable', n = 'London');
  SELECT o.name INTO n FROM core.staff_assignment a JOIN core.org_node o ON o.id = a.node_id
   WHERE a.staff_id='dddddddd-0000-0000-0000-000000000001' AND a.relation='primary_base' AND a.valid @> TIMESTAMPTZ '2025-09-03';
  PERFORM t('...and correctly answers Manchester after the transfer', n = 'Manchester');
END $$;

-- ============================================================ 13
\echo === 13. Row-level security isolates tenants for the application role ===
DO $$
DECLARE v_t2 uuid; n_all int; n_own int;
BEGIN
  INSERT INTO core.tenant (id, slug, name) VALUES ('aaaaaaaa-0000-0000-0000-000000000002','beta','Beta Inc') RETURNING id INTO v_t2;
  INSERT INTO core.principal (tenant_id, status, email, display_name) VALUES (v_t2, 'active', 'zed@beta.example', 'Zed');
  SELECT count(*) INTO n_all FROM core.principal;                 -- superuser sees all
  PERFORM set_config('app.tenant_id', 'aaaaaaaa-0000-0000-0000-000000000002', true);
  SET LOCAL ROLE app_runtime;
  SELECT count(*) INTO n_own FROM core.principal;                 -- app role sees its tenant only
  PERFORM t('app_runtime sees only its own tenant''s principals', n_own = 1 AND n_all > 1);
  -- views must not be a back door: consent_current runs as the caller (security_invoker)
  SELECT count(*) INTO n_own FROM privacy.consent_current;        -- Alice's consents belong to tenant 1
  PERFORM t('views honour row-level security (no superuser-owner bypass)', n_own = 0);
  RESET ROLE;
END $$;

ROLLBACK;   -- every fixture and every side effect above is discarded
DROP FUNCTION t(text, boolean);
DROP FUNCTION must_fail(text, text);
