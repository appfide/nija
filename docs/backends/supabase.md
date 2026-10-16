# Supabase

Direct client → Supabase project (PostgREST + Realtime). No server component.

## 1. Create the schema

Quickest: enter the project URL and key in the app and press **Test
connection & schema**. Then either

- **Set up automatically**: paste a [personal access
  token](https://supabase.com/dashboard/account/tokens) with database write
  access. Nija runs the setup through the Supabase Management API
  (`POST /v1/projects/{ref}/database/query`, currently in beta), sends the
  token only to `api.supabase.com` for that request, and does not store it.
  Revoke the token afterwards if you like; or
- **Copy setup SQL** and run it in the SQL Editor yourself.

The script is generated for your table names and sign-in mode; it creates
what is missing, upgrades older schemas, sets the row level security policy
and enables realtime, and is safe to run more than once.

Or by hand, run in **SQL Editor** (Dashboard → SQL → New query):

```sql
-- Items -----------------------------------------------------------------
create table if not exists public.clip_items (
  id            uuid primary key,
  owner_id      uuid default auth.uid(),          -- null when using anon key without sign-in
  device_id     text not null,
  device_name   text not null default '',
  content_type  text not null default 'text',
  content       text not null default '',
  blob_ref      text,
  content_hash  text not null,
  size_bytes    integer not null default 0,
  encrypted     boolean not null default false,
  nonce         text,
  created_at    timestamptz not null,
  updated_at    timestamptz not null,
  deleted_at    timestamptz,
  target_device_id text,                             -- "Send to…" one device
  key_version   integer not null default 0,          -- passphrase version
  sig           text                                 -- device signature
);
create index if not exists clip_items_updated_at_idx on public.clip_items (updated_at);
create index if not exists clip_items_owner_idx      on public.clip_items (owner_id);

-- Devices ---------------------------------------------------------------
create table if not exists public.devices (
  id          text primary key,
  owner_id    uuid default auth.uid(),
  name        text not null default '',
  platform    text not null default '',
  last_seen   timestamptz not null,
  app_version text,
  status      text not null default 'active',       -- active | paused | blocked | removed
  role        text not null default 'full',         -- full | send_only | receive_only
  expires_at  timestamptz,
  paired_by   text,
  sign_pub    text,                                 -- device Ed25519 public key
  box_pub     text,                                 -- device X25519 public key
  admin       boolean not null default false,
  admin_pub   text,
  membership_version integer not null default 0,
  membership_sig text,
  key_version integer not null default 0,
  key_envelope text,
  permissions text,                                 -- e.g. clear_history
  admin_envelope text                               -- admin key sealed to box_pub
);

-- Realtime --------------------------------------------------------------
alter publication supabase_realtime add table public.clip_items;
```

### Upgrading from 0.1.0

```sql
alter table public.clip_items
  add column if not exists target_device_id text,
  add column if not exists key_version integer not null default 0,
  add column if not exists sig text;
alter table public.devices
  add column if not exists app_version text,
  add column if not exists status      text not null default 'active',
  add column if not exists role        text not null default 'full',
  add column if not exists expires_at  timestamptz,
  add column if not exists paired_by   text,
  add column if not exists sign_pub    text,
  add column if not exists box_pub     text,
  add column if not exists admin       boolean not null default false,
  add column if not exists admin_pub   text,
  add column if not exists membership_version integer not null default 0,
  add column if not exists membership_sig text,
  add column if not exists key_version integer not null default 0,
  add column if not exists key_envelope text;
```

### Upgrading to 0.5

Needed only to grant permissions or make a member an admin from
*Manage devices*; everything else keeps working without it.

```sql
alter table public.devices
  add column if not exists permissions    text,
  add column if not exists admin_envelope text;
```

## 2. Lock it down (Row Level Security)

**Recommended: one Supabase Auth user per person.** Create the user under
Authentication → Users, then enter that email/password in the app. Rows are
scoped to `auth.uid()`:

```sql
alter table public.clip_items enable row level security;
alter table public.devices    enable row level security;

create policy "own items" on public.clip_items
  for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "own devices" on public.devices
  for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
```

**Not recommended: anon key only** (anyone with the key can read everything).
If you must, at least enable E2E encryption in the app:

```sql
create policy "anon all" on public.clip_items for all to anon using (true) with check (true);
create policy "anon all" on public.devices    for all to anon using (true) with check (true);
```

## 3. Optional: Storage bucket for large images/files

Storage → New bucket `clipboard` (private). Policy for authenticated users:

```sql
create policy "own objects" on storage.objects for all to authenticated
  using (bucket_id = 'clipboard' and owner = auth.uid())
  with check (bucket_id = 'clipboard' and owner = auth.uid());
```

## 4. App settings

| Field | Where to find it |
|---|---|
| Project URL | Settings → API → Project URL |
| Publishable (anon) key | Settings → API → `sb_publishable_…` (or legacy `anon` JWT) |
| Email / Password | The Auth user you created |
| Items table / Devices table | `clip_items` / `devices` unless renamed |
| Storage bucket | `clipboard` or empty |

Never enter the `service_role` / `sb_secret_` key: it bypasses RLS.

## Retention

The app's *purge older than N days* setting deletes rows via the API. To purge
server-side instead, schedule with `pg_cron`:

```sql
select cron.schedule('purge-clips', '0 3 * * *',
  $$delete from public.clip_items where updated_at < now() - interval '30 days'$$);
```
