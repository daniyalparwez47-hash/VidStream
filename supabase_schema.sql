-- YouTube Subscribe starter database schema for Supabase
-- Run this in Supabase SQL Editor. This creates app-owned community data.
-- It does NOT create or modify YouTube subscriptions or YouTube accounts.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'User',
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text default '',
  video_url text not null,
  thumbnail_url text,
  visibility text not null default 'public'
    check (visibility in ('public','unlisted','private')),
  created_at timestamptz not null default now()
);

create table if not exists public.subscriptions (
  subscriber_id uuid not null references auth.users(id) on delete cascade,
  channel_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (subscriber_id, channel_id),
  check (subscriber_id <> channel_id)
);

create table if not exists public.video_likes (
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, video_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table if not exists public.playlists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.playlist_videos (
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  position integer not null default 0,
  primary key (playlist_id, video_id)
);

create table if not exists public.watch_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  watched_at timestamptz not null default now(),
  primary key (user_id, video_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.videos enable row level security;
alter table public.subscriptions enable row level security;
alter table public.video_likes enable row level security;
alter table public.comments enable row level security;
alter table public.playlists enable row level security;
alter table public.playlist_videos enable row level security;
alter table public.watch_history enable row level security;
alter table public.notifications enable row level security;

-- Drop policies first so this setup script can be re-run safely.
DROP POLICY IF EXISTS "profiles readable" ON public.profiles;
DROP POLICY IF EXISTS "profile owner insert" ON public.profiles;
DROP POLICY IF EXISTS "profile owner update" ON public.profiles;
DROP POLICY IF EXISTS "public videos readable" ON public.videos;
DROP POLICY IF EXISTS "video owner insert" ON public.videos;
DROP POLICY IF EXISTS "video owner update" ON public.videos;
DROP POLICY IF EXISTS "video owner delete" ON public.videos;
DROP POLICY IF EXISTS "subscriptions readable" ON public.subscriptions;
DROP POLICY IF EXISTS "subscriber manages own" ON public.subscriptions;
DROP POLICY IF EXISTS "likes readable" ON public.video_likes;
DROP POLICY IF EXISTS "user manages own likes" ON public.video_likes;
DROP POLICY IF EXISTS "comments readable" ON public.comments;
DROP POLICY IF EXISTS "signed in comments" ON public.comments;
DROP POLICY IF EXISTS "comment owner delete" ON public.comments;
DROP POLICY IF EXISTS "playlist owner all" ON public.playlists;
DROP POLICY IF EXISTS "playlist videos visible" ON public.playlist_videos;
DROP POLICY IF EXISTS "playlist owner manages videos" ON public.playlist_videos;
DROP POLICY IF EXISTS "history owner only" ON public.watch_history;
DROP POLICY IF EXISTS "notifications owner only" ON public.notifications;
DROP POLICY IF EXISTS "authenticated upload own folder" ON storage.objects;
DROP POLICY IF EXISTS "owner reads own video files" ON storage.objects;
DROP POLICY IF EXISTS "owner deletes own video files" ON storage.objects;

-- Profiles: public read; owner writes own profile.
create policy "profiles readable" on public.profiles for select using (true);
create policy "profile owner insert" on public.profiles for insert with check (auth.uid() = id);
create policy "profile owner update" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- Videos: public/unlisted can be read; owners manage their own videos.
create policy "public videos readable" on public.videos for select using (visibility in ('public','unlisted') or auth.uid() = user_id);
create policy "video owner insert" on public.videos for insert with check (auth.uid() = user_id);
create policy "video owner update" on public.videos for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "video owner delete" on public.videos for delete using (auth.uid() = user_id);

-- User-owned interactions.
create policy "subscriptions readable" on public.subscriptions for select using (true);
create policy "subscriber manages own" on public.subscriptions for all using (auth.uid() = subscriber_id) with check (auth.uid() = subscriber_id);

create policy "likes readable" on public.video_likes for select using (true);
create policy "user manages own likes" on public.video_likes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "comments readable" on public.comments for select using (true);
create policy "signed in comments" on public.comments for insert with check (auth.uid() = user_id);
create policy "comment owner delete" on public.comments for delete using (auth.uid() = user_id);

create policy "playlist owner all" on public.playlists for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "playlist videos visible" on public.playlist_videos for select using (
  exists (select 1 from public.playlists p where p.id = playlist_id and (p.is_public or p.user_id = auth.uid()))
);
create policy "playlist owner manages videos" on public.playlist_videos for all using (
  exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
) with check (
  exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
);

create policy "history owner only" on public.watch_history for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "notifications owner only" on public.notifications for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Private video storage bucket. Upload/download policies are scoped to signed-in users.
insert into storage.buckets (id, name, public) values ('user-videos', 'user-videos', false)
on conflict (id) do nothing;

create policy "authenticated upload own folder" on storage.objects
for insert to authenticated
with check (bucket_id = 'user-videos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "owner reads own video files" on storage.objects
for select to authenticated
using (bucket_id = 'user-videos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "owner deletes own video files" on storage.objects
for delete to authenticated
using (bucket_id = 'user-videos' and (storage.foldername(name))[1] = auth.uid()::text);

-- Upgrade columns for the expanded VidStream client (safe to rerun).
ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS channel_name text;
ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'Entertainment';

-- Public video playback bucket. Uploads are limited to each signed-in user's folder.
INSERT INTO storage.buckets (id, name, public)
VALUES ('community-videos', 'community-videos', true)
ON CONFLICT (id) DO UPDATE SET public = true;
DROP POLICY IF EXISTS "community video owner uploads" ON storage.objects;
DROP POLICY IF EXISTS "community video owner deletes" ON storage.objects;
CREATE POLICY "community video owner uploads" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'community-videos' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "community video owner deletes" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'community-videos' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Expanded feature tables for VidStream (safe to rerun)
CREATE TABLE IF NOT EXISTS public.video_dislikes (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  video_id uuid NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, video_id)
);
CREATE TABLE IF NOT EXISTS public.video_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id uuid NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  viewed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS video_views_video_idx ON public.video_views(video_id);
CREATE INDEX IF NOT EXISTS video_views_date_idx ON public.video_views(viewed_at DESC);
ALTER TABLE public.video_dislikes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_views ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dislikes readable" ON public.video_dislikes;
DROP POLICY IF EXISTS "user manages own dislikes" ON public.video_dislikes;
DROP POLICY IF EXISTS "views readable aggregate" ON public.video_views;
DROP POLICY IF EXISTS "views insert allowed" ON public.video_views;
DROP POLICY IF EXISTS "user reads own views" ON public.video_views;
CREATE POLICY "dislikes readable" ON public.video_dislikes FOR SELECT USING (true);
CREATE POLICY "user manages own dislikes" ON public.video_dislikes FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "views readable aggregate" ON public.video_views FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "views insert allowed" ON public.video_views FOR INSERT WITH CHECK (user_id IS NULL OR auth.uid() = user_id);
CREATE POLICY "user reads own views" ON public.video_views FOR SELECT USING (auth.uid() = user_id);

-- VidStream monetization extension (manual-review prototype, safe to rerun)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'creator' CHECK (role IN ('creator','admin'));

CREATE OR REPLACE FUNCTION public.protect_profile_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NEW.role IS DISTINCT FROM OLD.role AND COALESCE((SELECT role FROM public.profiles WHERE id = auth.uid()), 'creator') <> 'admin' THEN
    RAISE EXCEPTION 'Only an admin can change profile roles';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS protect_profile_role_trigger ON public.profiles;
CREATE TRIGGER protect_profile_role_trigger BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_role();


CREATE TABLE IF NOT EXISTS public.monetization_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel_name text NOT NULL CHECK (char_length(channel_name) BETWEEN 1 AND 100),
  notes text DEFAULT '',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  review_note text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS monetization_apps_user_idx ON public.monetization_applications(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.creator_earnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount_usd numeric(12,2) NOT NULL CHECK (amount_usd <> 0),
  entry_type text NOT NULL CHECK (entry_type IN ('credit','adjustment')),
  description text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 500),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS creator_earnings_user_idx ON public.creator_earnings(creator_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.payout_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount_usd numeric(12,2) NOT NULL CHECK (amount_usd >= 10),
  payout_method text NOT NULL CHECK (char_length(payout_method) BETWEEN 2 AND 300),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','paid','rejected')),
  admin_note text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payout_requests_user_idx ON public.payout_requests(user_id, created_at DESC);

ALTER TABLE public.monetization_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.creator_earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payout_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "monetization app owner select" ON public.monetization_applications;
DROP POLICY IF EXISTS "monetization app owner insert" ON public.monetization_applications;
DROP POLICY IF EXISTS "monetization app admin select" ON public.monetization_applications;
DROP POLICY IF EXISTS "monetization app admin update" ON public.monetization_applications;
DROP POLICY IF EXISTS "earnings creator select" ON public.creator_earnings;
DROP POLICY IF EXISTS "earnings admin select" ON public.creator_earnings;
DROP POLICY IF EXISTS "earnings admin insert" ON public.creator_earnings;
DROP POLICY IF EXISTS "payout owner select" ON public.payout_requests;
DROP POLICY IF EXISTS "payout owner insert" ON public.payout_requests;
DROP POLICY IF EXISTS "payout admin select" ON public.payout_requests;
DROP POLICY IF EXISTS "payout admin update" ON public.payout_requests;

CREATE POLICY "monetization app owner select" ON public.monetization_applications
FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "monetization app owner insert" ON public.monetization_applications
FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND status = 'pending' AND reviewed_by IS NULL AND reviewed_at IS NULL);
CREATE POLICY "monetization app admin select" ON public.monetization_applications
FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));
CREATE POLICY "monetization app admin update" ON public.monetization_applications
FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'))
WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));

CREATE POLICY "earnings creator select" ON public.creator_earnings
FOR SELECT TO authenticated USING (creator_id = auth.uid());
CREATE POLICY "earnings admin select" ON public.creator_earnings
FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));
CREATE POLICY "earnings admin insert" ON public.creator_earnings
FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));

CREATE POLICY "payout owner select" ON public.payout_requests
FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "payout owner insert" ON public.payout_requests
FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND status = 'pending' AND reviewed_by IS NULL AND reviewed_at IS NULL);
CREATE POLICY "payout admin select" ON public.payout_requests
FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));
CREATE POLICY "payout admin update" ON public.payout_requests
FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'))
WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));

-- Admin role is granted manually by a trusted project owner after a user exists.
-- Example (replace the email with the trusted administrator account):
-- UPDATE public.profiles SET role = 'admin' WHERE id = (SELECT id FROM auth.users WHERE email = 'admin@example.com');

-- Enforce creator approval and prevent requesting more than the earned balance.
CREATE OR REPLACE FUNCTION public.validate_creator_payout_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  earned numeric(12,2);
  reserved numeric(12,2);
  approved_creator boolean;
BEGIN
  IF NEW.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Payout request must belong to the signed-in user';
  END IF;
  -- Serialize payout requests for the creator to prevent concurrent double-spend.
  PERFORM 1 FROM public.profiles WHERE id = NEW.user_id FOR UPDATE;
  SELECT EXISTS (SELECT 1 FROM public.monetization_applications ma
    WHERE ma.user_id = NEW.user_id AND ma.status = 'approved' AND ma.created_at = (SELECT max(ma2.created_at) FROM public.monetization_applications ma2 WHERE ma2.user_id = NEW.user_id)) INTO approved_creator;
  IF NOT approved_creator THEN
    RAISE EXCEPTION 'Creator monetization application must be approved before requesting a payout';
  END IF;
  SELECT COALESCE(sum(amount_usd),0) INTO earned FROM public.creator_earnings WHERE creator_id = NEW.user_id;
  SELECT COALESCE(sum(amount_usd),0) INTO reserved FROM public.payout_requests
    WHERE user_id = NEW.user_id AND status IN ('pending','approved','paid');
  IF NEW.amount_usd > GREATEST(earned - reserved, 0) THEN
    RAISE EXCEPTION 'Payout amount exceeds available earnings';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS validate_creator_payout_trigger ON public.payout_requests;
CREATE TRIGGER validate_creator_payout_trigger BEFORE INSERT ON public.payout_requests
FOR EACH ROW EXECUTE FUNCTION public.validate_creator_payout_request();

-- Admin-managed sponsored placements shown as clearly labeled ads in the home feed.
CREATE TABLE IF NOT EXISTS public.ad_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
  target_url text NOT NULL,
  image_url text,
  active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ad_campaigns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "active campaigns public read" ON public.ad_campaigns;
DROP POLICY IF EXISTS "campaign admin insert" ON public.ad_campaigns;
DROP POLICY IF EXISTS "campaign admin update" ON public.ad_campaigns;
DROP POLICY IF EXISTS "campaign admin delete" ON public.ad_campaigns;
CREATE POLICY "active campaigns public read" ON public.ad_campaigns FOR SELECT USING (active = true OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));
CREATE POLICY "campaign admin insert" ON public.ad_campaigns FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));
CREATE POLICY "campaign admin update" ON public.ad_campaigns FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin')) WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));
CREATE POLICY "campaign admin delete" ON public.ad_campaigns FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));


-- Automatically create a default creator profile on account signup.
CREATE OR REPLACE FUNCTION public.create_vidstream_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, role)
  VALUES (NEW.id, COALESCE(NULLIF(NEW.raw_user_meta_data->>'display_name',''), split_part(NEW.email,'@',1), 'Creator'), 'creator')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS on_auth_user_created_vidstream_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_vidstream_profile AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.create_vidstream_profile();

-- Backfill profiles for users created before this profile trigger was installed.
INSERT INTO public.profiles (id, display_name, role)
SELECT u.id, COALESCE(NULLIF(u.raw_user_meta_data->>'display_name',''), split_part(u.email,'@',1), 'Creator'), 'creator'
FROM auth.users u
ON CONFLICT (id) DO NOTHING;
CREATE UNIQUE INDEX IF NOT EXISTS one_pending_monetization_application_per_user
ON public.monetization_applications(user_id) WHERE status = 'pending';

-- Cloud view-count RPC: exposes aggregate counts only, not individual viewer records.
CREATE OR REPLACE FUNCTION public.get_video_view_counts(p_video_ids uuid[])
RETURNS TABLE(video_id uuid, view_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT vv.video_id, COUNT(*)::bigint AS view_count
  FROM public.video_views vv
  WHERE vv.video_id = ANY(p_video_ids)
  GROUP BY vv.video_id;
REVOKE ALL ON FUNCTION public.get_video_view_counts(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_video_view_counts(uuid[]) TO anon, authenticated;

-- Ensure public aggregate access uses the RPC, while raw view records remain protected.
DROP POLICY IF EXISTS "views readable aggregate" ON public.video_views;
CREATE POLICY "views readable aggregate" ON public.video_views FOR SELECT USING (auth.uid() = user_id);
