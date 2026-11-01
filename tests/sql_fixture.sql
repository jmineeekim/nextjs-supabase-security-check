-- 테스트용: Supabase와 비슷한 최소 환경(역할, auth.uid())과 일부러 잘못 만든 객체
do $$ begin
  create role anon;
exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated;
exception when duplicate_object then null; end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
create function auth.role() returns text language sql stable as $$ select 'anon'::text $$;
grant usage on schema public to anon, authenticated;

-- 구멍 2: RLS 없는 테이블
create table public.orders (id int, user_id uuid, amount int);

-- 올바른 예: RLS + 본인 조건 정책
create table public.reservations (id int, user_id uuid, status text);
alter table public.reservations enable row level security;
create policy "own_select" on public.reservations
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own_update" on public.reservations
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- 구멍 2: 로그인만 확인하는 정책, 모두 허용 정책
create table public.profiles (id uuid, nickname text, avatar_url text, role text);
alter table public.profiles enable row level security;
create policy "loose" on public.profiles
  for update to authenticated using (auth.role() = 'authenticated') with check (true);
create policy "public_read" on public.profiles for select using (true);

-- 구멍 2: security_invoker 없는 view, materialized view
create view public.v_bad as select * from public.reservations;
create view public.v_ok with (security_invoker = true) as select * from public.reservations;
create materialized view public.mv as select 1 as x;

-- 구멍 4: 테이블 전체 update 권한 (role 컬럼까지 쓸 수 있음)
grant select, insert, update on public.profiles to authenticated;
