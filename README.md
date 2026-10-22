# Threadly
Communities, posts, votes and comments. Works on phone, tablet and laptop (installable as an app).

- **Communities** you can join or create, **text / link / image posts**, **upvote and downvote**, **nested comments**, Hot / New / Top sorting, search, saved posts, user profiles with karma, report buttons, delete for authors and community creators, a family-friendly word filter, dark and light themes.
- **Demo mode (default):** everything is saved on your own device only, so you can try it right away.
- **Online mode:** connect your own free [Supabase](https://supabase.com) project so friends see the same posts.

## Set up online mode (about 10 minutes)
1. Make a free Supabase account and a new project.
2. SQL Editor → paste all of [`supabase-schema.sql`](supabase-schema.sql) → **Run**.
3. Authentication → Providers → Email → switch **Confirm email** OFF (accounts use a username, not a real email).
4. Project Settings → API → copy the **Project URL** and the **anon public** key.
5. In the app: Settings → Online mode → paste them → **Connect**. (Or put them in `config.js` before publishing.)

Notes: pictures are shrunk and stored inside posts, so this suits a small community. Supabase's free plan pauses after a week of no use. The anon key is meant to be public; the table rules in the SQL file are what keep data safe.

Open / install: see `download.html`.
