#!/usr/bin/env bash
# sql/ 쿼리를 PostgreSQL에 실행해 기대한 결과가 나오는지 확인합니다.
# 필요: psql, 그리고 빈 테스트 DB 접속 정보(PG* 환경변수). 예) PGHOST=localhost PGUSER=postgres
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
q() { psql -X -q -At -v ON_ERROR_STOP=1 "$@"; }

q -f "$ROOT/tests/sql_fixture.sql"

fail=0
expect() { # expect <설명> <기대값> <실제값>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (기대: $2 / 실제: $3)"; fail=1; fi
}

expect "01 RLS 꺼진 테이블" "orders" "$(q -f "$ROOT/sql/01_rls_disabled_tables.sql")"
expect "02 본인 조건 없는 정책" "loose,public_read" \
  "$(q -f "$ROOT/sql/02_policies_without_owner.sql" | cut -d'|' -f2 | paste -sd,)"
expect "03 security_invoker 없는 view" "mv,v_bad" \
  "$(q -f "$ROOT/sql/03_views_without_security_invoker.sql" | cut -d'|' -f1 | paste -sd,)"
expect "04 role 컬럼 권한 (수정 전)" "t|t|f|f" "$(q -f "$ROOT/sql/04_column_privileges.sql")"

# fix_examples.sql 적용 후 다시 확인
q -c "drop policy own_select on public.reservations; drop policy own_update on public.reservations;"
q -f "$ROOT/sql/fix_examples.sql"
expect "04 role 컬럼 권한 (수정 후)" "f|f|f|f" "$(q -f "$ROOT/sql/04_column_privileges.sql")"

exit $fail
