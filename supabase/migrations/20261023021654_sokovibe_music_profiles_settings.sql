-- SokoVibe Music user profile and preference tables.
-- Apply after creating the Supabase project r yaqkhoattdaghusbiuz.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (display_name is null or char_length(display_name) between 1 and 80)
);

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  language text not null default 'sw-TZ',
  theme text not null default 'system',
  autoplay boolean not null default false,
  audio_quality text not null default 'standard',
  explicit_content boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint user_settings_language_allowed check (language in ('sw-TZ', 'en')),
  constraint user_settings_theme_allowed check (theme in ('system', 'light', 'dark')),
  constraint user_settings_audio_quality_allowed check (audio_quality in ('low', 'standard', 'high'))
);

alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;

revoke all on public.profiles from anon, authenticated;
revoke all on public.user_settings from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.user_settings to authenticated;

create policy "profiles_select_own" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles_update_own" on public.profiles
  for update to authenticated using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "user_settings_select_own" on public.user_settings
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "user_settings_insert_own" on public.user_settings
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "user_settings_update_own" on public.user_settings
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "user_settings_delete_own" on public.user_settings
  for delete to authenticated using ((select auth.uid()) = user_id);

create or replace function public.handle_new_sokovibe_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name', '')), '')
  )
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_sokovibe_user() from public, anon, authenticated;
create trigger on_auth_user_created_sokovibe
  after insert on auth.users
  for each row execute function public.handle_new_sokovibe_user();
