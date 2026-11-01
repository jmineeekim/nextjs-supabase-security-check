# nextjs-supabase-security-check

[![ci](https://github.com/jmineeekim/nextjs-supabase-security-check/actions/workflows/ci.yml/badge.svg)](https://github.com/jmineeekim/nextjs-supabase-security-check/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

AI 코딩 도구로 만든 **Next.js + Supabase** 프로젝트를 배포하기 전에, 가장 흔한 보안 구멍 5가지를 점검하는 셸 스크립트와 SQL 모음입니다.

```bash
curl -fsSL -o check.sh https://raw.githubusercontent.com/jmineeekim/nextjs-supabase-security-check/v0.1.0/scripts/check.sh
chmod +x check.sh
./check.sh --build .
```

- 의존성 없음: `bash`, `grep`, `git`만 씁니다. (`--build`를 쓰면 `npm`도 필요)
- DB에 접속하지 않습니다. DB 점검은 Supabase SQL Editor에 붙여 넣는 SQL로 합니다.
- **비밀 값 원문을 출력하지 않습니다.** 파일 이름과 줄 번호만 보여 줍니다.
- FAIL이 하나라도 있으면 종료 코드 1을 돌려줘서 CI에 그대로 넣을 수 있습니다.

## 점검하는 구멍 5가지

AI 코딩 도구는 권한 오류가 나면 권한을 넓혀서 "해결"하는 경향이 있습니다. 그렇게 생기는 구멍은 정상 사용자로 테스트하면 보이지 않습니다.

| # | 구멍 | `check.sh` (코드·빌드) | `sql/` (DB) |
|---|---|---|---|
| 1 | 비밀 키가 브라우저로 간다 | `NEXT_PUBLIC_`이 붙은 비밀 변수, `server-only` 누락, 빌드 결과물 속 비밀 값 | – |
| 2 | RLS가 꺼진 테이블 | 마이그레이션의 RLS 누락, `using (true)` | RLS 꺼진 테이블, 본인 조건 없는 정책, `security_invoker` 없는 view |
| 3 | 로그인만 확인하고 주인은 확인하지 않는다 | Server Action·Route Handler 목록, 서버 코드의 `getSession()` | – |
| 4 | 사용자가 보낸 값을 그대로 믿는다 | 요청 값을 금액·권한 필드에 바로 넣는 패턴 | 권한 컬럼(`role` 등)의 쓰기 권한 |
| 5 | Git과 로그에 남는 비밀 | 추적 중인 `.env`, 이력 속 `sb_secret_` 키, `.gitignore`, 요청 본문을 찍는 로그, `error.message` | – |

판정은 세 가지입니다.

| 판정 | 뜻 |
|---|---|
| **FAIL** | 확실한 문제. 배포 전에 고쳐야 합니다 |
| **WARN** | 자동으로 판정할 수 없는 항목. 표시된 파일을 직접 검토하세요 |
| **PASS** | 이 스크립트가 찾는 패턴은 없음 (안전하다는 보장은 아님) |

## 실행 예시

`NEXT_PUBLIC_SUPABASE_SECRET_KEY`를 클라이언트 컴포넌트에서 쓴 Next.js 16 프로젝트(supabase-js 포함)를 빌드해 점검한 실제 출력입니다.

```text
[1] 비밀 키가 브라우저로 가는가
  FAIL  NEXT_PUBLIC_ 이 붙은 비밀 변수 이름이 있습니다 (빌드 시 브라우저 코드에 포함됨)
        .env.local:1
        app/leak.tsx:2
  WARN  secret key를 읽는 파일에 import 'server-only' 가 없습니다 (클라이언트에서 import 되면 빌드가 막히지 않음)
        app/leak.tsx
  INFO  npm run build 실행 중...
  FAIL  빌드 결과물에 비밀 값이 있습니다 (파일 이름만 표시)
        .next/static/chunks/12afh3tl19exs.js
        .next/server/app/index.html
```

브라우저로 가는 JS 청크뿐 아니라, 서버가 미리 만들어 둔 HTML(`.next/server/app`)에도 키가 들어간 것을 볼 수 있습니다. 고친 뒤에는 이렇게 나옵니다.

```text
결과  FAIL 0 · WARN 0 · PASS 7
```

## 사용법

```text
./check.sh [옵션] [프로젝트 경로]

  --build            npm run build 를 실행한 뒤 빌드 결과물을 검사합니다
  --secret <조각>     빌드 결과물에서 찾을 비밀 값 일부 (여러 번 지정 가능)
  --no-color         색 없이 출력합니다
  -h, --help         도움말
```

`sb_secret_`로 시작하는 키는 자동으로 찾습니다. supabase-js 라이브러리 코드 자체에 `sb_secret_`라는 글자가 들어 있어서, 접두사만으로 검색하면 브라우저용 Supabase 클라이언트를 쓰는 모든 프로젝트가 걸립니다. 그래서 접두사 뒤에 20자 이상이 붙은 경우만 키로 봅니다. **결제 비밀 키, 암호화 키, 레거시 `service_role` JWT 키**처럼 접두사가 없는 값은 `--secret`으로 끝 20자 정도를 넘겨야 찾습니다. 레거시 JWT 키는 앞부분이 공개용 `anon` 키와 같아서, 반드시 **끝부분**으로 검색해야 구분됩니다.

```bash
# 셸 기록에 남기지 않으려면 환경변수로 (줄바꿈으로 여러 개)
SECRET_FRAGMENTS="$(tail -c 21 <<< "$SUPABASE_SECRET_KEY")" ./check.sh --build .
```

## DB 점검 (Supabase SQL Editor)

Supabase 대시보드 → SQL Editor에서 `sql/` 폴더의 쿼리를 실행합니다.

| 파일 | 통과 기준 |
|---|---|
| [`01_rls_disabled_tables.sql`](sql/01_rls_disabled_tables.sql) | 0행 |
| [`02_policies_without_owner.sql`](sql/02_policies_without_owner.sql) | 나온 정책이 모두 공개해도 되는 데이터 |
| [`03_views_without_security_invoker.sql`](sql/03_views_without_security_invoker.sql) | 0행 |
| [`04_column_privileges.sql`](sql/04_column_privileges.sql) | 네 값 모두 `false` |

고치는 방법 예시는 [`sql/fix_examples.sql`](sql/fix_examples.sql)에 있습니다. 대시보드의 **Security Advisor** 경고도 함께 확인하세요.

## CI에 넣기

[`examples/github-actions.yml`](examples/github-actions.yml)을 내 프로젝트의 `.github/workflows/`에 복사하세요. Git 이력 검사를 위해 `fetch-depth: 0`이 필요하고, 스크립트는 `main`이 아니라 **태그나 커밋 해시로 고정**해서 받는 것을 권장합니다.

## 예제 코드

| 파일 | 내용 |
|---|---|
| [`examples/supabase-admin.ts`](examples/supabase-admin.ts) | `server-only`로 막아 둔 관리자 클라이언트 |
| [`examples/server-action.ts`](examples/server-action.ts) | 주인 조건과 0건 수정 확인이 들어간 Server Action |
| [`examples/gitignore.txt`](examples/gitignore.txt), [`examples/env.example`](examples/env.example) | `.env` 관리 |

## 한계

- **패턴 검색입니다.** 코드를 이해하지 못하므로 놓치는 것도, 잘못 잡는 것도 있습니다. WARN은 반드시 직접 검토하세요.
- 테스트 계정 두 개로 "A로 로그인해서 B의 데이터 수정"을 직접 시도해 보는 점검(구멍 3)은 대신해 주지 않습니다. 판정은 화면 응답이 아니라 Table Editor에서 B의 데이터가 그대로인지로 하세요.
- Git 이력 검사는 `sb_secret_` 키만 찾습니다. 다른 비밀까지 보려면 [gitleaks](https://github.com/gitleaks/gitleaks)를 `--redact` 옵션과 함께 쓰세요.
- 모든 검사를 통과해도 안전하다는 보장은 아닙니다.

## 테스트

```bash
bash tests/test_check.sh                            # 문제 있는 프로젝트 / 고친 프로젝트에 check.sh 실행
PGHOST=localhost PGUSER=postgres bash tests/test_sql.sh  # 빈 PostgreSQL에 sql/ 쿼리 실행
```

Next.js 16.4.3 + @supabase/supabase-js 실제 빌드, PostgreSQL 16에서 확인했습니다. CI에서 shellcheck와 두 테스트를 실행합니다.

## 더 자세한 설명

각 구멍이 왜 생기는지, 암호화·키 관리·개인정보 보호법, 배포 전 체크리스트 55항목은 이 저장소를 만든 사람이 쓴 PDF 전자책 「[1인 개발자를 위한 쉬운 보안 설명서](https://www.latpeed.com/products/UbsH7)」(유료)에 정리했습니다. 이 저장소의 스크립트와 SQL은 책 없이도 그대로 쓸 수 있습니다.

## 라이선스

[MIT](LICENSE). 이 저장소는 법률 자문이 아니며, 점검 결과에 대한 책임은 사용자에게 있습니다.
