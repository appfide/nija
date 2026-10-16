# CouchDB / IBM Cloudant

Plain HTTP API; the app talks straight to the database. Works with Apache
CouchDB ≥ 3.0 and Cloudant.

## 1. Create the database and index

```sh
export COUCH=https://couch.example.com:5984
export AUTH=admin:YOUR_PASSWORD          # admin only for setup

curl -u $AUTH -X PUT $COUCH/nija

curl -u $AUTH -X POST $COUCH/nija/_index \
  -H 'Content-Type: application/json' \
  -d '{"index":{"fields":["kind","updated_at"]},"name":"kind-updated_at","type":"json"}'
```

Document layout (one database, discriminated by `kind`):

| `_id` | `kind` | fields |
|---|---|---|
| `clip:<uuid>` | `clip` | `device_id, device_name, content_type, content, blob_ref, content_hash, size_bytes, encrypted, nonce, created_at, updated_at, deleted_at, target_device_id, key_version, sig` |
| `device:<uuid>` | `device` | `name, platform, last_seen, app_version, status, role, expires_at, paired_by, sign_pub, box_pub, admin, admin_pub, membership_version, membership_sig, key_version, key_envelope, permissions, admin_envelope` (see [devices.md](../devices.md)) |

No migration is needed from 0.1.0; documents are schema-less.

Large binaries are stored as CouchDB attachments on the clip document.

## 2. Create a per-user account (do not use admin in the app)

```sh
curl -u $AUTH -X PUT $COUCH/_users/org.couchdb.user:alice \
  -H 'Content-Type: application/json' \
  -d '{"name":"alice","password":"YOUR_PASSWORD","roles":[],"type":"user"}'

curl -u $AUTH -X PUT $COUCH/nija/_security \
  -H 'Content-Type: application/json' \
  -d '{"admins":{"names":[],"roles":[]},"members":{"names":["alice"],"roles":[]}}'
```

For Cloudant use *Manage → Permissions* to grant `_reader`/`_writer` to an
API key and enter the key/password in the app.

## 3. App settings

| Field | Value |
|---|---|
| Server URL | `https://couch.example.com:5984` |
| Database name | `nija` |
| Username / Password | `alice` / … |

Enable CORS if you also use the web build: `curl -u $AUTH -X PUT $COUCH/_node/_local/_config/httpd/enable_cors -d '"true"'`.

## Retention

The app's purge deletes old docs via `_bulk_docs`. Run periodic compaction:
`curl -u $AUTH -X POST $COUCH/nija/_compact`.
