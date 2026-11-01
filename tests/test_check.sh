#!/usr/bin/env bash
# scripts/check.sh 를 임시 프로젝트 두 개(문제 있는 것, 고친 것)에 실행해 결과를 확인합니다.
# 가짜 비밀 값은 저장소에 문자열로 두지 않고 실행 중에 만듭니다(비밀 탐지 도구 오탐 방지).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PREFIX="sb_""secret_"
FAKE="${PREFIX}TESTONLY0000000000000000"

git_init() { git -C "$1" init -q && git -C "$1" -c user.email=t@t -c user.name=t add -A && \
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm init; }

# ── 문제 있는 프로젝트 ──
BAD="$TMP/bad"
mkdir -p "$BAD/app/api/reservations" "$BAD/lib/supabase" "$BAD/.next/static/chunks" "$BAD/.next/server/app" "$BAD/supabase/migrations"
cat > "$BAD/.env" <<EOF
NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY=$FAKE
EOF
cat > "$BAD/lib/supabase/admin.ts" <<'EOF'
import { createClient } from '@supabase/supabase-js'
export const supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SECRET_KEY!)
EOF
cat > "$BAD/app/actions.ts" <<'EOF'
'use server'
export async function cancel(id: string, body: any) {
  console.log('body', body)
  const { data: { session } } = await supabase.auth.getSession()
  await supabase.from('orders').insert({ amount: body.amount })
}
EOF
cat > "$BAD/app/api/reservations/route.ts" <<'EOF'
export async function POST(req: Request) { return Response.json({ ok: true }) }
EOF
echo "var k=\"$FAKE\";" > "$BAD/.next/static/chunks/main.js"
echo "<html></html>" > "$BAD/.next/server/app/index.html"
cat > "$BAD/supabase/migrations/0001_init.sql" <<'EOF'
create table public.orders (id int, user_id uuid, amount int);
create table public.reservations (id int, user_id uuid);
alter table public.reservations enable row level security;
create policy "all" on public.reservations for select using (true);
EOF
git_init "$BAD"

# ── 고친 프로젝트 ──
GOOD="$TMP/good"
mkdir -p "$GOOD/app" "$GOOD/lib/supabase" "$GOOD/.next/static/chunks" "$GOOD/.next/server/app" "$GOOD/supabase/migrations"
printf '.env*\n!.env.example\n' > "$GOOD/.gitignore"
echo "SUPABASE_SECRET_KEY=$FAKE" > "$GOOD/.env.local"
cat > "$GOOD/lib/supabase/admin.ts" <<'EOF'
import 'server-only'
import { createClient } from '@supabase/supabase-js'
export const supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SECRET_KEY!)
EOF
echo "export default function Page() { return null }" > "$GOOD/app/page.tsx"
echo "var u=1;" > "$GOOD/.next/static/chunks/main.js"
echo "<html></html>" > "$GOOD/.next/server/app/index.html"
cat > "$GOOD/supabase/migrations/0001_init.sql" <<'EOF'
create table public.reservations (id int, user_id uuid);
alter table public.reservations enable row level security;
create policy "own_select" on public.reservations for select to authenticated using ((select auth.uid()) = user_id);
EOF
git_init "$GOOD"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

out=$(bash "$CHECK" --no-color "$BAD" 2>&1) && code=0 || code=$?
[ "$code" -eq 1 ] && ok "문제 프로젝트: 종료 코드 1" || bad "문제 프로젝트: 종료 코드 $code"
for want in \
  "FAIL  NEXT_PUBLIC_ 이 붙은 비밀 변수" \
  "WARN  secret key를 읽는 파일에 import 'server-only'" \
  "FAIL  빌드 결과물에 비밀 값이 있습니다" \
  "WARN  마이그레이션에서 RLS를 켜지 않은 테이블" \
  "WARN  using (true)" \
  "WARN  서버 코드에서 getSession()" \
  "WARN  요청 값으로 금액·권한" \
  "FAIL  Git이 추적 중인 .env 파일" \
  "FAIL  Git 이력에 sb_secret_" \
  "WARN  .gitignore 에 .env* 패턴이 없습니다" \
  "WARN  요청 본문·사용자 정보를 로그로"; do
  grep -qF -- "$want" <<< "$out" && ok "문제 프로젝트: $want" || bad "문제 프로젝트: '$want' 없음"
done
grep -qF "$FAKE" <<< "$out" && bad "출력에 비밀 값 원문이 있음" || ok "출력에 비밀 값 원문 없음"

out=$(bash "$CHECK" --no-color "$GOOD" 2>&1) && code=0 || code=$?
[ "$code" -eq 0 ] && ok "고친 프로젝트: 종료 코드 0" || { bad "고친 프로젝트: 종료 코드 $code"; echo "$out"; }
grep -q "FAIL  " <<< "$out" && bad "고친 프로젝트에 FAIL 있음" || ok "고친 프로젝트: FAIL 없음"

# --secret 옵션: 접두사 없는 비밀 값도 찾는지
echo "var p=\"PAYKEY-TESTONLY-1234567890\";" > "$GOOD/.next/static/chunks/pay.js"
out=$(bash "$CHECK" --no-color --secret "TESTONLY-1234567890" "$GOOD" 2>&1) && code=0 || code=$?
[ "$code" -eq 1 ] && grep -qF "pay.js" <<< "$out" && ok "--secret 으로 접두사 없는 값 탐지" || bad "--secret 탐지 실패"

exit $fail
