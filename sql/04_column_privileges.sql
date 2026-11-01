-- [구멍 4] 사용자가 쓰면 안 되는 컬럼에 쓰기 권한이 있는가
-- 통과 기준: 네 값이 모두 false
--   public.profiles 의 role 컬럼 예시입니다. 가격·포인트 같은 다른 민감 컬럼은
--   테이블 이름과 컬럼 이름만 바꿔 실행하세요.
select
  has_column_privilege('authenticated', 'public.profiles', 'role', 'INSERT') as auth_insert,
  has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE') as auth_update,
  has_column_privilege('anon',          'public.profiles', 'role', 'INSERT') as anon_insert,
  has_column_privilege('anon',          'public.profiles', 'role', 'UPDATE') as anon_update;
