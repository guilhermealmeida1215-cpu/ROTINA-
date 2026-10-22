-- ROTINA+ | Banco completo para Supabase. Cole no SQL Editor e execute uma vez.
create table public.profiles(
  id uuid primary key references auth.users on delete cascade,
  display_name text, tz text not null default 'America/Sao_Paulo',
  xp int not null default 0, level int not null default 1, created_at timestamptz default now());
create table public.challenges(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  title text not null check (char_length(title) between 1 and 80),
  category text not null default 'outro' check (category in ('agua','alimentacao','banheiro','sono','tarefa','outro')),
  target numeric not null default 1 check (target > 0), step numeric not null default 1 check (step > 0),
  unit text not null default 'vez', due_time time, active boolean not null default true,
  created_at timestamptz default now());
create table public.daily_logs(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  challenge_id uuid not null references public.challenges on delete cascade,
  log_date date not null default current_date, value numeric not null default 0 check (value >= 0),
  completed boolean not null default false, on_time boolean not null default false, completed_at timestamptz,
  unique(challenge_id, log_date));
create table public.badges(code text primary key, name text not null, description text not null, icon text not null);
create table public.user_badges(
  user_id uuid references auth.users on delete cascade, code text references public.badges, earned_at timestamptz default now(),
  primary key(user_id, code));
create table public.rewards(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  title text not null check (char_length(title) between 1 and 80), min_level int not null default 2 check (min_level >= 1),
  claimed_at timestamptz, created_at timestamptz default now());

insert into public.badges values
('total_1','Primeiro passo','Cumpriu sua primeira meta','🥉'),
('total_10','Constante','10 metas cumpridas','🥈'),
('total_50','Disciplinado','50 metas cumpridas','🥇'),
('total_100','Imparável','100 metas cumpridas','🏆'),
('ontime_10','Pontual','10 metas cumpridas no horário','⏰'),
('level_5','Nível 5','Chegou ao nível 5','⭐');

-- Segurança: RLS em tudo; cada pessoa só enxerga e altera os próprios dados
alter table public.profiles enable row level security;
alter table public.challenges enable row level security;
alter table public.daily_logs enable row level security;
alter table public.user_badges enable row level security;
alter table public.rewards enable row level security;
alter table public.badges enable row level security;
create policy p_sel on public.profiles for select using (id = auth.uid());
create policy p_upd on public.profiles for update using (id = auth.uid());
create policy c_all on public.challenges for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy l_all on public.daily_logs for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy r_all on public.rewards for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ub_sel on public.user_badges for select using (user_id = auth.uid());
create policy b_sel on public.badges for select using (true);
-- XP e nível NÃO podem ser alterados pelo usuário (só pelos gatilhos)
revoke update on public.profiles from anon, authenticated;
grant update (display_name, tz) on public.profiles to authenticated;
revoke all on public.user_badges from anon, authenticated; grant select on public.user_badges to authenticated;

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id, display_name) values (new.id, split_part(new.email,'@',1)); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Calcula conclusão e pontualidade no servidor (o app não consegue forjar)
create function public.log_before() returns trigger language plpgsql security definer set search_path=public as $$
declare t numeric; d time; z text; was boolean := false;
begin
  select target, due_time into t, d from challenges where id = new.challenge_id and user_id = new.user_id;
  if t is null then raise exception 'desafio inválido'; end if;
  select tz into z from profiles where id = new.user_id;
  if tg_op = 'INSERT' then new.log_date := (now() at time zone z)::date; else was := old.completed; new.log_date := old.log_date; end if;
  if was then new.completed := true; new.on_time := old.on_time; new.completed_at := old.completed_at;
  elsif new.value >= t then new.completed := true; new.completed_at := now(); new.on_time := d is null or (now() at time zone z)::time <= d;
  else new.completed := false; new.on_time := false; new.completed_at := null; end if;
  return new;
end $$;
create trigger log_b before insert or update on public.daily_logs for each row execute function public.log_before();

create function public.log_after() returns trigger language plpgsql security definer set search_path=public as $$
declare n int; o int; xp_new int; lv int;
begin
  if new.completed and (tg_op = 'INSERT' or not old.completed) then
    update profiles set xp = xp + 10 + (case when new.on_time then 5 else 0 end) where id = new.user_id returning xp into xp_new;
    lv := xp_new / 200 + 1; update profiles set level = lv where id = new.user_id;
    select count(*), count(*) filter (where on_time) into n, o from daily_logs where user_id = new.user_id and completed;
    insert into user_badges(user_id, code) select new.user_id, c from (values
      (case when n>=1 then 'total_1' end),(case when n>=10 then 'total_10' end),(case when n>=50 then 'total_50' end),
      (case when n>=100 then 'total_100' end),(case when o>=10 then 'ontime_10' end),(case when lv>=5 then 'level_5' end)) v(c)
    where c is not null on conflict do nothing;
  end if; return null;
end $$;
create trigger log_a after insert or update on public.daily_logs for each row execute function public.log_after();

-- Prêmio só pode ser resgatado se o nível for suficiente
create function public.reward_check() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.claimed_at is not null and old.claimed_at is null and (select level from profiles where id = new.user_id) < new.min_level
  then raise exception 'nível insuficiente'; end if; return new; end $$;
create trigger reward_b before update on public.rewards for each row execute function public.reward_check();
