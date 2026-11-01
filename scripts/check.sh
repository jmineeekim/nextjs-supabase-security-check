#!/usr/bin/env bash
# nextjs-supabase-security-check
# Next.js + Supabase 프로젝트를 배포하기 전에 흔한 보안 구멍을 점검합니다.
#
# 사용법:
#   ./check.sh [옵션] [프로젝트 경로]
#
# 옵션:
#   --build            npm run build 를 실행한 뒤 빌드 결과물을 검사합니다
#   --secret <조각>     빌드 결과물에서 찾을 비밀 값 일부 (여러 번 지정 가능)
#                      환경변수 SECRET_FRAGMENTS 에 줄바꿈으로 구분해 넣어도 됩니다
#   --no-color         색 없이 출력합니다
#   -h, --help         도움말
#
# 종료 코드: 0 = FAIL 없음, 1 = FAIL 있음, 2 = 사용법 오류
#
# 비밀 값 원문은 출력하지 않습니다. 파일 이름(과 필요한 경우 줄 번호)만 출력합니다.

set -uo pipefail

VERSION="0.1.0"
RUN_BUILD=0
COLOR=1
TARGET="."
SECRETS=()
SB_SECRET_RE="sb_secret_[A-Za-z0-9_-]{20,}"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --build) RUN_BUILD=1 ;;
    --secret)
      [ $# -ge 2 ] || { echo "--secret 뒤에 값이 필요합니다" >&2; exit 2; }
      SECRETS+=("$2"); shift ;;
    --no-color) COLOR=0 ;;
    -h|--help) usage; exit 0 ;;
    -v|--version) echo "$VERSION"; exit 0 ;;
    -*) echo "알 수 없는 옵션: $1" >&2; usage >&2; exit 2 ;;
    *) TARGET="$1" ;;
  esac
  shift
done

if [ -n "${SECRET_FRAGMENTS:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && SECRETS+=("$line")
  done <<< "$SECRET_FRAGMENTS"
fi

cd "$TARGET" 2>/dev/null || { echo "경로를 열 수 없습니다: $TARGET" >&2; exit 2; }

if [ "$COLOR" -eq 1 ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
  RED=""; YEL=""; GRN=""; DIM=""; BLD=""; RST=""
fi

FAILS=0; WARNS=0; PASSES=0
pass() { PASSES=$((PASSES + 1)); printf '  %sPASS%s  %s\n' "$GRN" "$RST" "$1"; }
warn() { WARNS=$((WARNS + 1));   printf '  %sWARN%s  %s\n' "$YEL" "$RST" "$1"; }
fail() { FAILS=$((FAILS + 1));   printf '  %sFAIL%s  %s\n' "$RED" "$RST" "$1"; }
info() { printf '  %sINFO%s  %s\n' "$DIM" "$RST" "$1"; }
detail() { while IFS= read -r l; do [ -n "$l" ] && printf '        %s%s%s\n' "$DIM" "$l" "$RST"; done; }
section() { printf '\n%s%s%s\n' "$BLD" "$1" "$RST"; }

# 검사 대상 소스 폴더 (있는 것만)
SRC_DIRS=()
for d in app src lib components pages utils; do [ -d "$d" ] && SRC_DIRS+=("$d"); done

src_grep() {
  # src_grep <grep 옵션...>  — 소스 폴더가 없으면 아무것도 출력하지 않음
  [ ${#SRC_DIRS[@]} -eq 0 ] && return 1
  grep -r --exclude-dir=node_modules --exclude-dir=.next "$@" "${SRC_DIRS[@]}" 2>/dev/null
}

printf '%snextjs-supabase-security-check v%s%s\n' "$BLD" "$VERSION" "$RST"
printf '대상: %s\n' "$(pwd)"

# ──────────────────────────────────────────────
section "[1] 비밀 키가 브라우저로 가는가"

# 1-a. NEXT_PUBLIC_ 이 붙은 비밀 변수 이름
pub_secret=$( {
  src_grep -nE "NEXT_PUBLIC_[A-Z0-9_]*(SECRET|SERVICE_ROLE|PRIVATE)[A-Z0-9_]*"
  for f in .env .env.local .env.production .env.development .env.example; do
    [ -f "$f" ] && grep -nE "^[[:space:]]*NEXT_PUBLIC_[A-Z0-9_]*(SECRET|SERVICE_ROLE|PRIVATE)" "$f" 2>/dev/null | sed "s|^|$f:|"
  done
} | cut -d: -f1,2 | sort -u)
if [ -n "$pub_secret" ]; then
  fail "NEXT_PUBLIC_ 이 붙은 비밀 변수 이름이 있습니다 (빌드 시 브라우저 코드에 포함됨)"
  echo "$pub_secret" | detail
else
  pass "NEXT_PUBLIC_ 이 붙은 SECRET / SERVICE_ROLE / PRIVATE 변수 없음"
fi

# 1-b. secret key를 읽는 파일에 'server-only' 가 있는가
admin_files=$(src_grep -lE "SUPABASE_SECRET_KEY|SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY" | sort -u)
if [ -z "$admin_files" ]; then
  info "secret key 환경변수를 읽는 파일 없음"
else
  missing=""
  while IFS= read -r f; do
    grep -qE "^[[:space:]]*import[[:space:]]+['\"]server-only['\"]" "$f" || missing+="$f"$'\n'
  done <<< "$admin_files"
  if [ -n "$missing" ]; then
    warn "secret key를 읽는 파일에 import 'server-only' 가 없습니다 (클라이언트에서 import 되면 빌드가 막히지 않음)"
    printf '%s' "$missing" | detail
  else
    pass "secret key를 읽는 파일 모두 import 'server-only' 사용"
  fi
fi

# 1-c. 빌드 결과물 검사
BUILD_OK=1
if [ "$RUN_BUILD" -eq 1 ]; then
  BUILD_LOG="${TMPDIR:-/tmp}/nssc-build.log"
  info "npm run build 실행 중..."
  if ! npm run build >"$BUILD_LOG" 2>&1; then
    BUILD_OK=0
    fail "빌드 실패. 이전 빌드 결과물로 판정하지 않도록 검사를 건너뜁니다 (로그: $BUILD_LOG)"
  fi
fi
if [ "$BUILD_OK" -eq 0 ]; then
  :
elif [ -d .next/static ] && [ -d .next/server/app ]; then
  # supabase-js 자체에 "sb_secret_" 문자열이 들어 있으므로 접두사만으로 찾으면 오탐이 납니다.
  # 접두사 뒤에 실제 키처럼 긴 값이 붙은 경우만 찾습니다.
  hits=$(grep -rlE "$SB_SECRET_RE" .next/static .next/server/app 2>/dev/null)
  if [ ${#SECRETS[@]} -gt 0 ]; then
    pats=(); for s in "${SECRETS[@]}"; do pats+=(-e "$s"); done
    hits=$(printf '%s\n%s\n' "$hits" "$(grep -rlF "${pats[@]}" .next/static .next/server/app 2>/dev/null)" | grep . | sort -u)
  fi
  if [ -n "$hits" ]; then
    fail "빌드 결과물에 비밀 값이 있습니다 (파일 이름만 표시)"
    echo "$hits" | detail
  else
    pass "빌드 결과물(.next/static, .next/server/app)에서 비밀 값을 찾지 못함 (sb_secret_ 키 + 직접 지정 ${#SECRETS[@]}개)"
  fi
  [ ${#SECRETS[@]} -eq 0 ] && info "접두사 없는 비밀 값(결제 키, 암호화 키, 레거시 JWT 키)은 --secret 으로 끝 20자 정도를 넘겨야 찾습니다"
else
  info "빌드 결과물(.next)이 없어 건너뜀. --build 옵션을 주거나 먼저 빌드하세요"
fi

# ──────────────────────────────────────────────
section "[2] RLS가 꺼진 테이블"
info "DB 점검은 Supabase SQL Editor에서 sql/ 폴더의 쿼리를 실행하세요 (이 스크립트는 DB에 접속하지 않습니다)"
MIG=()
[ -d supabase/migrations ] && while IFS= read -r f; do MIG+=("$f"); done < <(find supabase/migrations -name "*.sql" | sort)
if [ ${#MIG[@]} -gt 0 ]; then
  created=$(grep -hoiE "create table( if not exists)?[[:space:]]+(public\.)?\"?[a-z0-9_]+" "${MIG[@]}" \
    | awk '{print $NF}' | sed 's/^public\.//; s/"//g' | sort -u)
  no_rls=""
  for t in $created; do
    grep -qiE "alter table( only)?[[:space:]]+(public\.)?\"?$t\"?[[:space:]]+enable row level security" "${MIG[@]}" \
      || no_rls+="$t"$'\n'
  done
  if [ -n "$no_rls" ]; then
    warn "마이그레이션에서 RLS를 켜지 않은 테이블 (DB에서 직접 켰다면 sql/01 로 확인)"
    printf '%s' "$no_rls" | detail
  else
    pass "마이그레이션의 모든 테이블에 enable row level security 있음"
  fi
  loose=$(grep -nE "(using|with check)[[:space:]]*\([[:space:]]*true[[:space:]]*\)" "${MIG[@]}" | cut -d: -f1,2)
  if [ -n "$loose" ]; then
    warn "using (true) / with check (true) 정책이 있습니다. 공개해도 되는 데이터인지 확인하세요"
    echo "$loose" | detail
  fi
else
  info "supabase/migrations 폴더 없음"
fi

# ──────────────────────────────────────────────
section "[3] 로그인만 확인하고 주인은 확인하지 않는 코드"
actions=$(src_grep -lE "^[[:space:]]*['\"]use server['\"]" | sort -u)
routes=$( [ ${#SRC_DIRS[@]} -eq 0 ] || find "${SRC_DIRS[@]}" -path '*/node_modules' -prune -o -type f -name 'route.*' -print 2>/dev/null | sort)
admin_use=$(src_grep -lE "supabaseAdmin|createAdminClient|SUPABASE_SECRET_KEY|SERVICE_ROLE" | sort -u)
cnt() { [ -z "$1" ] && echo 0 || echo "$1" | grep -c .; }
info "Server Action 파일 $(cnt "$actions")개, Route Handler $(cnt "$routes")개, 관리자 클라이언트 사용 파일 $(cnt "$admin_use")개"
if [ -n "$actions$routes" ]; then
  warn "아래 파일의 함수마다 '로그인 확인 + 주인 조건(user_id)'이 있는지 직접 검토하세요"
  printf '%s\n%s\n' "$actions" "$routes" | sort -u | detail
fi
session=$(src_grep -nE "auth\.getSession\(" | cut -d: -f1,2)
if [ -n "$session" ]; then
  warn "서버 코드에서 getSession()을 씁니다. 서버 검증에는 getClaims() 또는 getUser()를 쓰세요"
  echo "$session" | detail
fi

# ──────────────────────────────────────────────
section "[4] 사용자가 보낸 값을 그대로 믿는 코드"
info "권한·금액 컬럼의 쓰기 권한은 sql/04_column_privileges.sql 로 확인하세요"
money=$(src_grep -nE "(price|amount|role|point|discount)[\"']?[[:space:]]*:[[:space:]]*(body|formData|req|request|input|data)\." | cut -d: -f1,2)
if [ -n "$money" ]; then
  warn "요청 값으로 금액·권한을 정하는 것처럼 보이는 줄 (서버가 DB에서 다시 조회해야 함)"
  echo "$money" | detail
else
  pass "요청 값을 금액·권한 필드에 바로 넣는 패턴을 찾지 못함 (패턴 검색이므로 직접 검토도 필요)"
fi

# ──────────────────────────────────────────────
section "[5] Git과 로그에 남는 비밀"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_env=$(git ls-files | grep -E "(^|/)\.env" | grep -vE "(^|/)\.env\.example$")
  if [ -n "$tracked_env" ]; then
    fail "Git이 추적 중인 .env 파일이 있습니다 (git rm --cached 후 안의 키를 교체하세요)"
    echo "$tracked_env" | detail
  else
    pass "Git이 추적하는 .env 파일 없음 (.env.example 제외)"
  fi
  leaked=$(git log --all -G "$SB_SECRET_RE" --format='%h %s' 2>/dev/null | head -20)
  if [ -n "$leaked" ]; then
    fail "Git 이력에 sb_secret_ 키가 들어간 커밋이 있습니다. 이력 삭제보다 키 교체가 먼저입니다"
    echo "$leaked" | detail
  else
    pass "Git 이력에서 sb_secret_ 를 찾지 못함 (다른 비밀은 gitleaks 권장)"
  fi
else
  info "Git 저장소가 아니라 Git 검사를 건너뜀"
fi
if [ -f .gitignore ] && grep -qE "^\.env(\*|\.\*|$)" .gitignore; then
  pass ".gitignore 에 .env 패턴 있음"
else
  warn ".gitignore 에 .env* 패턴이 없습니다 (examples/gitignore.txt 참고)"
fi
logs=$(src_grep -nE "console\.(log|error|warn|info|debug)\(.*(body|formData|user|req|request|password|token)" | cut -d: -f1,2)
if [ -n "$logs" ]; then
  warn "요청 본문·사용자 정보를 로그로 남길 수 있는 줄"
  echo "$logs" | detail
else
  pass "요청 본문·사용자 정보를 찍는 console 로그를 찾지 못함"
fi
errmsg=$(src_grep -nE "error\.message" | cut -d: -f1,2)
if [ -n "$errmsg" ]; then
  warn "error.message 를 쓰는 곳. 사용자 응답에 DB 오류 원문을 담지 않는지 확인하세요"
  echo "$errmsg" | detail
fi

# ──────────────────────────────────────────────
printf '\n%s결과%s  %sFAIL %d%s · %sWARN %d%s · %sPASS %d%s\n' \
  "$BLD" "$RST" "$RED" "$FAILS" "$RST" "$YEL" "$WARNS" "$RST" "$GRN" "$PASSES" "$RST"
[ "$WARNS" -gt 0 ] && printf '%sWARN은 자동으로 판정할 수 없는 항목입니다. 표시된 파일을 직접 검토하세요.%s\n' "$DIM" "$RST"
[ "$FAILS" -gt 0 ] && exit 1
exit 0
