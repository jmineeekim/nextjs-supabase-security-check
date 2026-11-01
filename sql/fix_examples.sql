-- 고치는 방법 예시 (그대로 실행하기 전에 테이블·컬럼 이름을 내 프로젝트에 맞게 바꾸세요)

-- 1) RLS 켜기 + 본인 데이터만 다루는 정책 (reservations 테이블, user_id 컬럼 예시)
alter table public.reservations enable row level security;

create policy "own_select" on public.reservations
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "own_insert" on public.reservations
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "own_update" on public.reservations
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- 2) view는 조회하는 사람 권한으로 실행
-- create view public.my_view with (security_invoker = true) as select ...;

-- 3) 권한 컬럼(role)은 사용자가 쓸 수 없게 컬럼 단위로 권한 제한
--    (가장 권장하는 방법은 권한 정보를 별도 테이블로 분리하는 것입니다)
revoke insert, update on public.profiles from anon, authenticated;
grant insert (id, nickname, avatar_url) on public.profiles to authenticated;
grant update (nickname, avatar_url)     on public.profiles to authenticated;
-- 이 설정에서는 supabase-js 의 upsert 가 권한 오류를 냅니다. 프로필 수정에는 update 를 쓰세요.
