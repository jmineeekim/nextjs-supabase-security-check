-- [구멍 2] security_invoker 가 없는 view / materialized view
-- 통과 기준: 0행
--   public 스키마의 view는 기본적으로 만든 사람 권한으로 실행되어 원본 테이블의 RLS를 건너뛸 수 있습니다.
--   relkind = 'm' 은 materialized view 입니다. RLS가 적용되지 않으므로 public 스키마에 두지 마세요.
select c.relname, c.relkind
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('v', 'm')
  and not exists (
    select 1 from unnest(coalesce(c.reloptions, '{}')) o
    where o in ('security_invoker=true', 'security_invoker=on',
                'security_invoker=1', 'security_invoker=yes'))
order by c.relname;
