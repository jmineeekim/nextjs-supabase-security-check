-- [구멍 2] 본인 조건(auth.uid())이 없는 정책
-- 통과 기준: 나온 정책이 모두 "공개해도 되는 데이터"에 대한 것
--   using (true), auth.role() = 'authenticated' 같은 "로그인만 하면 허용" 정책을 잡아냅니다.
--   auth.uid() is not null 처럼 로그인 여부만 보는 조건은 이 쿼리로 걸리지 않으니 눈으로도 확인하세요.
--   roles 에 {public} 이 보이면 to authenticated 없이 만든 정책입니다(비로그인 사용자에게도 적용).
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and ((qual is not null and qual not like '%auth.uid()%')
    or (with_check is not null and with_check not like '%auth.uid()%'))
order by tablename, policyname;
