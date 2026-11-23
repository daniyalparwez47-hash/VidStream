VIDSTREAM - YouTube-style video platform prototype (expanded build)

WHAT IS INCLUDED
- Responsive browse/home feed, category filters and search
- Video player page (YouTube embed + uploaded community videos)
- Shorts vertical feed (vertical layout; uploaded videos categorized Shorts)
- Like/dislike, Watch Later, Share controls
- Channel profile pages and local subscriptions
- Comments for cloud community uploads (Supabase)
- Email signup/login using Supabase Auth
- Video uploads to Supabase Storage (100 MB client-side limit)
- Local playlists, watch history, view counter, notification inbox
- Creator Studio view, channel bio editor (local), delete cloud video entry
- Dark theme and mobile layout

SETUP
1. Extract ZIP.
2. Open Supabase project > SQL Editor.
3. Run the full supabase_schema.sql script included in this ZIP.
4. Check www/supabase-config.js: it has the project's URL and public/publishable key.
5. Deploy the www folder to a static host over HTTPS, or run locally using a static server.
6. Sign up/login to upload and test cloud video/comment features.

IMPORTANT LIMITS (NOT A FULL YOUTUBE REPLICA)
- This is an independent YouTube-inspired prototype; it is not YouTube and does not connect to YouTube accounts.
- Community-video likes/dislikes and creator-channel subscriptions sync to Supabase when signed in (requires schema policies).
- Likes/dislikes/subscriptions for sample YouTube videos, saved videos, history, playlists, notifications, and channel bio remain device-local.
- Cloud video uploads and comments use Supabase. Upload size limit in this client is 100 MB.
- Cloud uploads use a public playback bucket; uploaded video files can be viewed by anyone with the URL.
- Shorts are a vertical feed layout, not YouTube's proprietary Shorts backend/recommendation system.
- Creator Studio metrics are basic/local and not true analytics.
- There is no secure admin/moderation role, copyright management, livestreaming, ads/monetization,
  recommendation algorithm, transcoding, CDN, or native official YouTube subscription integration.
- For production: implement server-side roles, backend interaction tables/RPC, moderation,
  upload resumability, transcoding, storage privacy, abuse controls, and scalable streaming.

MONETIZATION / EARNING FEATURES (prototype)
- Monetization page: creator applies, sees approval status and earnings ledger.
- Payout requests: minimum USD $10; server-side SQL trigger checks approval and balance.
- Admin panel: admin reviews applications and payout requests, manually records verified earnings, and creates/pauses sponsored campaigns.
- Home feed: active campaigns show as clearly labeled Sponsored placements.
- IMPORTANT: This is a manual-review prototype. It is NOT connected to an advertising network, advertiser billing, tax compliance, KYC, or automatic payment provider. Money is not sent by the app.

Setup:
1. Run the full updated supabase_schema.sql in Supabase SQL Editor (safe rerun policies/objects).
2. Create/sign in to the trusted admin account in the app first, so its profile row is created.
3. In Supabase SQL Editor, grant admin role to the trusted account:
   UPDATE public.profiles SET role='admin' WHERE id=(SELECT id FROM auth.users WHERE email='YOUR_ADMIN_EMAIL');
4. Refresh the app, open More > Admin Panel. Admin can approve creators, review payouts, add manually verified ledger entries, and publish sponsored campaigns.
5. Users open More > Monetization to apply. Only approved creators can request payout.

Do not paste payment passwords, card PINs, or bank login credentials into payout details.

CLOUD INTERACTIONS UPDATE
- When signed in, community-upload likes/dislikes use video_likes/video_dislikes tables.
- Subscriptions to community creators sync through the subscriptions table (creator UUID mapping).
- Interactions on sample/YouTube-linked videos remain local because they are not VidStream database video records.
- Sign out and sign back in to refresh cloud-synced interactions.

NEW CLOUD UPDATE
- Cloud watch history sync (logged-in users)
- Cloud video view events for Supabase community uploads
- Aggregate cloud view-count RPC (counts only; no raw viewer list exposed by the RPC)
- Run the FULL updated supabase_schema.sql again in Supabase SQL Editor to create the RPC.
