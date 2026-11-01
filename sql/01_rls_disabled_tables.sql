-- [구멍 2] RLS가 꺼진 테이블
-- 통과 기준: 0행
-- 실행 위치: Supabase 대시보드 > SQL Editor
select tablename
from pg_tables
where schemaname = 'public'
  and rowsecurity = false
order by tablename;
