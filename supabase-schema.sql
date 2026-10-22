-- Nestly server setup for Supabase. Paste ALL of this into: Supabase > SQL Editor > New query > Run.
-- Then switch OFF "Confirm email" under Authentication > Providers > Email.

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  created timestamptz not null default now()
);
create unique index if not exists profiles_username_ci on profiles (lower(username));

create table if not exists communities (
  name text primary key check (name ~ '^[A-Za-z0-9_]{3,21}$'),
  title text not null check (char_length(title) <= 60),
  description text not null default '' check (char_length(description) <= 300),
  creator uuid references profiles(id) on delete set null,
  created timestamptz not null default now()
);

create table if not exists members (
  user_id uuid not null references profiles(id) on delete cascade,
  community text not null references communities(name) on delete cascade,
  primary key (user_id, community)
);

create table if not exists posts (
  id bigint generated always as identity primary key,
  community text not null references communities(name) on delete cascade,
  author uuid not null references profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 300),
  body text not null default '' check (char_length(body) <= 10000),
  url text not null default '' check (char_length(url) <= 2000),
  image text not null default '' check (char_length(image) <= 600000),
  created timestamptz not null default now()
);
create index if not exists posts_community_idx on posts (community, created desc);

create table if not exists comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references posts(id) on delete cascade,
  parent_id bigint references comments(id) on delete cascade,
  author uuid not null references profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  created timestamptz not null default now()
);
create index if not exists comments_post_idx on comments (post_id, created);

create table if not exists votes (
  user_id uuid not null references profiles(id) on delete cascade,
  kind text not null check (kind in ('post', 'comment')),
  target bigint not null,
  value smallint not null check (value in (-1, 1)),
  primary key (user_id, kind, target)
);
create index if not exists votes_target_idx on votes (kind, target);

create table if not exists saved (
  user_id uuid not null references profiles(id) on delete cascade,
  post_id bigint not null references posts(id) on delete cascade,
  created timestamptz not null default now(),
  primary key (user_id, post_id)
);

create table if not exists reports (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  kind text not null check (kind in ('post', 'comment')),
  target bigint not null,
  reason text not null default '',
  created timestamptz not null default now()
);

-- Read-only views the app uses (they add scores, comment counts and usernames).
create or replace view communities_v as
  select c.name, c.title, c.description, c.created, pr.username as creator,
         (select count(*) from members m where m.community = c.name)::int as members
  from communities c left join profiles pr on pr.id = c.creator;

create or replace view posts_v as
  select p.id, p.community, p.title, p.body, p.url, p.image, p.created, pr.username as author,
         coalesce((select sum(v.value) from votes v where v.kind = 'post' and v.target = p.id), 0)::int as score,
         (select count(*) from comments c where c.post_id = p.id)::int as comments
  from posts p join profiles pr on pr.id = p.author;

create or replace view comments_v as
  select c.id, c.post_id, c.parent_id, c.body, c.created, pr.username as author,
         coalesce((select sum(v.value) from votes v where v.kind = 'comment' and v.target = c.id), 0)::int as score
  from comments c join profiles pr on pr.id = c.author;

grant select on communities_v, posts_v, comments_v to anon, authenticated;

-- Safety rules (Row Level Security): who may read and change what.
alter table profiles enable row level security;
alter table communities enable row level security;
alter table members enable row level security;
alter table posts enable row level security;
alter table comments enable row level security;
alter table votes enable row level security;
alter table saved enable row level security;
alter table reports enable row level security;

drop policy if exists profiles_read on profiles;
drop policy if exists profiles_add on profiles;
drop policy if exists comm_read on communities;
drop policy if exists comm_add on communities;
drop policy if exists mem_read on members;
drop policy if exists mem_add on members;
drop policy if exists mem_del on members;
drop policy if exists posts_read on posts;
drop policy if exists posts_add on posts;
drop policy if exists posts_del on posts;
drop policy if exists cm_read on comments;
drop policy if exists cm_add on comments;
drop policy if exists cm_del on comments;
drop policy if exists votes_read on votes;
drop policy if exists votes_add on votes;
drop policy if exists votes_edit on votes;
drop policy if exists votes_del on votes;
drop policy if exists saved_all on saved;
drop policy if exists reports_add on reports;

create policy profiles_read on profiles for select using (true);
create policy profiles_add on profiles for insert to authenticated with check (auth.uid() = id);

create policy comm_read on communities for select using (true);
create policy comm_add on communities for insert to authenticated with check (auth.uid() = creator);

create policy mem_read on members for select using (true);
create policy mem_add on members for insert to authenticated with check (auth.uid() = user_id);
create policy mem_del on members for delete to authenticated using (auth.uid() = user_id);

create policy posts_read on posts for select using (true);
create policy posts_add on posts for insert to authenticated with check (auth.uid() = author);
create policy posts_del on posts for delete to authenticated using (
  auth.uid() = author or exists (select 1 from communities c where c.name = posts.community and c.creator = auth.uid())
);

create policy cm_read on comments for select using (true);
create policy cm_add on comments for insert to authenticated with check (auth.uid() = author);
create policy cm_del on comments for delete to authenticated using (
  auth.uid() = author or exists (
    select 1 from posts p join communities c on c.name = p.community
    where p.id = comments.post_id and c.creator = auth.uid())
);

create policy votes_read on votes for select to authenticated using (auth.uid() = user_id);
create policy votes_add on votes for insert to authenticated with check (auth.uid() = user_id);
create policy votes_edit on votes for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy votes_del on votes for delete to authenticated using (auth.uid() = user_id);

create policy saved_all on saved for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy reports_add on reports for insert to authenticated with check (auth.uid() = user_id);
-- Reports can be read only by you in the Supabase dashboard (Table Editor > reports).

-- A few starter communities so the app is not empty (created by nobody, so only you can moderate via the dashboard).
insert into communities (name, title, description) values
  ('general', 'General', 'Talk about anything.'),
  ('gaming', 'Gaming', 'Video games, tips and clips.'),
  ('school', 'School Help', 'Homework help and study tips.'),
  ('funny', 'Funny', 'Clean jokes and funny stories.')
on conflict (name) do nothing;
