# PocketBase

Self-hosted single binary (`./pocketbase serve`). SSE realtime. Direct client
access; no extra server.

## 1. Import collections

Admin UI → Settings → Import collections → paste:

```json
[
  {
    "name": "clip_items",
    "type": "base",
    "fields": [
      { "name": "clip_id",      "type": "text",   "required": true, "max": 64 },
      { "name": "device_id",    "type": "text",   "required": true },
      { "name": "device_name",  "type": "text" },
      { "name": "content_type", "type": "text",   "required": true },
      { "name": "content",      "type": "text",   "max": 2000000 },
      { "name": "blob_ref",     "type": "text" },
      { "name": "blob",         "type": "file",   "maxSelect": 1, "maxSize": 26214400 },
      { "name": "content_hash", "type": "text",   "required": true },
      { "name": "size_bytes",   "type": "number" },
      { "name": "encrypted",    "type": "bool" },
      { "name": "nonce",        "type": "text" },
      { "name": "created_at",   "type": "date",   "required": true },
      { "name": "updated_at",   "type": "date",   "required": true },
      { "name": "deleted_at",   "type": "date" },
      { "name": "target_device_id", "type": "text" },
      { "name": "key_version",  "type": "number" },
      { "name": "sig",          "type": "text" },
      { "name": "owner",        "type": "relation", "collectionId": "_pb_users_auth_", "maxSelect": 1 }
    ],
    "indexes": [
      "CREATE UNIQUE INDEX idx_clip_items_clip_id ON clip_items (clip_id)",
      "CREATE INDEX idx_clip_items_updated_at ON clip_items (updated_at)"
    ],
    "listRule":   "@request.auth.id != '' && owner = @request.auth.id",
    "viewRule":   "@request.auth.id != '' && owner = @request.auth.id",
    "createRule": "@request.auth.id != '' && owner = @request.auth.id",
    "updateRule": "@request.auth.id != '' && owner = @request.auth.id",
    "deleteRule": "@request.auth.id != '' && owner = @request.auth.id"
  },
  {
    "name": "devices",
    "type": "base",
    "fields": [
      { "name": "device_id", "type": "text", "required": true },
      { "name": "name",      "type": "text" },
      { "name": "platform",  "type": "text" },
      { "name": "last_seen", "type": "date", "required": true },
      { "name": "app_version", "type": "text" },
      { "name": "status",    "type": "text" },
      { "name": "role",      "type": "text" },
      { "name": "expires_at","type": "date" },
      { "name": "paired_by", "type": "text" },
      { "name": "sign_pub",  "type": "text" },
      { "name": "box_pub",   "type": "text" },
      { "name": "admin",     "type": "bool" },
      { "name": "admin_pub", "type": "text" },
      { "name": "membership_version", "type": "number" },
      { "name": "membership_sig", "type": "text" },
      { "name": "key_version", "type": "number" },
      { "name": "key_envelope", "type": "text", "max": 4096 },
      { "name": "permissions", "type": "text" },
      { "name": "admin_envelope", "type": "text", "max": 4096 },
      { "name": "owner",     "type": "relation", "collectionId": "_pb_users_auth_", "maxSelect": 1 }
    ],
    "indexes": [ "CREATE UNIQUE INDEX idx_devices_device_id ON devices (device_id)" ],
    "listRule":   "@request.auth.id != '' && owner = @request.auth.id",
    "viewRule":   "@request.auth.id != '' && owner = @request.auth.id",
    "createRule": "@request.auth.id != '' && owner = @request.auth.id",
    "updateRule": "@request.auth.id != '' && owner = @request.auth.id",
    "deleteRule": "@request.auth.id != '' && owner = @request.auth.id"
  }
]
```

The app sets `owner` to the signed-in user automatically when the `owner`
field exists. Set every rule to `""` (empty = public) only for a private LAN
instance, and enable E2E encryption regardless.

### Upgrading from 0.1.0

Add the fields marked above to the existing collections (Collections → edit
→ New field): `target_device_id`, `sig` (text) and `key_version` (number) on
`clip_items`; `app_version`, `status`, `role`, `paired_by`, `sign_pub`,
`box_pub`, `admin_pub`, `membership_sig`, `key_envelope` (text),
`admin` (bool), `membership_version`, `key_version` (number) and
`expires_at` (date) on `devices`.
PocketBase silently drops unknown fields, so the app checks for them and
refuses to sync until they exist.

### Upgrading to 0.5

Add `permissions` and `admin_envelope` (text) to `devices`. They are needed
only to grant permissions or make a member an admin; without them the app
refuses the grant and leaves the device as it was.

## 2. Create a user

Collections → `users` → New record (email + password). Enter these in the app.
To use a superuser instead, set *Auth collection* to `_superusers`.

## 3. App settings

| Field | Value |
|---|---|
| Server URL | `https://pb.example.com` (or `http://192.168.1.10:8090` on LAN) |
| Auth collection | `users` |
| Email / Password | The user above |
| Items / Devices collection | `clip_items` / `devices` |

## Retention

Settings → Backups is separate. To auto-purge, add a cron in `pb_hooks/purge.pb.js`:

```js
cronAdd("purge-clips", "0 3 * * *", () => {
  const cutoff = new Date(Date.now() - 30 * 864e5).toISOString().replace("T", " ");
  $app.db().newQuery("DELETE FROM clip_items WHERE updated_at < {:c}").bind({ c: cutoff }).execute();
});
```
