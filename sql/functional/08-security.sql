-- 보안 (docs/04 §8). 전 항목 설정 작업을 수반한다.
-- F-90, F-92 미충족은 결격 조건 K4 에 해당하므로 즉시 보고한다.

-- @check F-90 | security | 인증 (LDAP / OAuth2 / Kerberos / mTLS) | mode=manual
select 1;

-- @check F-91 | security | 전송 구간 TLS | mode=manual
select 1;

-- @check F-92 | security | RBAC (역할, GRANT/REVOKE)
create role if not exists fn_test_role;
-- @fallback engine=starrocks
create role fn_test_role;

-- @check F-93 | security | 컬럼 마스킹 / 행 수준 필터 | mode=manual
select 1;

-- @check F-94 | security | 감사 로그 (쿼리 이력) | mode=manual
select 1;

-- @check F-95 | security | 외부 권한 시스템 연동 (Ranger 등) | mode=manual
select 1;
