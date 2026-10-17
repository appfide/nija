# Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ apps/nija (Flutter)                               │
│  platform/   clipboard capture · tray · hotkeys · autostart │
│  data/local  drift (SQLite): items + outbox + cursor        │
│  features/   history · settings · devices (pair / manage)  │
└───────────────┬─────────────────────────────────────────────┘
                │ LocalStore, SyncBackend, ClipCipher
┌───────────────▼─────────────────────────────────────────────┐
│ packages/nija_core (pure Dart)                          │
│  model/      ClipItem · Device (status/role/expiry)         │
│  sync/       SyncEngine (push · pull · membership check)    │
│  crypto/     ClipCipher · DeviceKeys · ClipSigning ·        │
│              KeyEnvelope · CipherRing                        │
│  pairing/    PairingPayload · PairingCodec (PIN-sealed)     │
│  backend/    SyncBackend · BackendDescriptor · ConfigField  │
│  backends/   supabase · pocketbase · couchdb · firestore ·  │
│              mongodb · memory                               │
└───────────────┬─────────────────────────────────────────────┘
                │ direct client connection (user's credentials)
        ┌───────▼────────┐
        │ user's database│  ← no Appfide server anywhere
        └────────────────┘
```

## Data flow

1. **Capture**: platform clipboard watcher (desktop: polling change-count;
   mobile: on app resume / share sheet) produces a `ClipItem` with a SHA-256
   `content_hash`. It is written to the local drift table with `synced = false`.
2. **Push**: `SyncEngine` drains unsynced rows in batches, optionally sealing
   `content` with `ClipCipher`, and calls `backend.upsert`.
3. **Pull**: `backend.pullSince(cursor)` returns rows from *other* devices
   ordered by `updated_at`; items are decrypted, echo-suppressed by hash, and
   applied last-writer-wins. The cursor advances to the max `updated_at`.
4. **Realtime**: where the backend supports it (Supabase, PocketBase,
   CouchDB, memory), `watch()` events simply trigger step 3. Polling backends
   (Firestore, MongoDB) run step 3 on a timer.
5. **Delete**: tombstone (`deleted_at`, content blanked). Rows are physically
   removed only by retention (`purgeBefore`).
6. **Membership**: every minute (and before a sync older than that) the
   engine lists `devices`, refreshes its own presence row, verifies each
   row's admin signature and version, adopts its role and any key envelope
   addressed to it, and ignores clips from untrusted / blocked / expired
   devices and items addressed to another device. If its own signed row
   says blocked, removed or expired, it stops with `SyncPhase.revoked` and
   the app wipes credentials, passphrases and trust state.
7. **Signing**: every pushed item is sealed (newest `CipherRing` key) and
   then signed with the device's Ed25519 key; every pulled item is verified
   against the sender's admin-signed public key before decryption. Threat
   model and limits: [devices.md](devices.md#how-access-is-enforced--read-this).
8. **Deadlines**: the engine wraps the backend in `TimedBackend`, so every
   request fails as a transient error after 20 seconds (device rows) or
   2 minutes (clips) instead of waiting forever on a dead connection.
   Clipboard capture never waits for the engine to connect.

## One database at a time

A device syncs with exactly one database: the one selected in *Settings →
Database*. Credentials for others you set up before stay saved, so switching
back does not mean typing them again, but nothing is read from or sent to a
database that is not selected. A database is identified by its type and its
address (`backendScope`, such as `supabase|https://<ref>.supabase.co`), so
two Supabase projects are two databases.

Switching to another database:

- starts reading the new one from the beginning (the read position is reset);
- marks the history already on the device *Only on this device*
  (`local_only`): none of it is in the new database and none of it is sent
  there, so a new database never receives old history unasked. Clips the new
  database already holds turn back to *In &lt;database&gt;* when pulled;
- keeps the admin key and pinned admin per database, so a signed group on
  one does not carry over to the other. The encryption keyring belongs to
  the device, not the database: joining the new group by pairing replaces
  it, and typing credentials by hand keeps the passphrase you enter.

Each history row shows which of the three states a clip is in: *In
&lt;database&gt;* (`synced`), *Waiting to sync* (in the outbox) or *Only on
this device* (`local_only`: copied while database sync was off, the device
was paused or receive-only, or before a switch).

## Adding a backend

Implement `SyncBackend`, declare a `BackendDescriptor` (the settings form is
rendered from `configSchema`), register in `BackendRegistry.builtIn()`, run
`runBackendContractTests`, write `docs/backends/<id>.md`, and add credential
patterns to `.gitleaks.toml`.

## Security model

- Pairing codes carry the database settings encrypted under an 8-digit PIN
  (Argon2id 64 MiB → AES-256-GCM), valid for 5 minutes, never recorded in
  history. Access decisions (role, expiry) are written by the host before the
  code is shown.
- Device access control is cryptographic: per-device Ed25519 identities,
  admin-signed membership rows with rollback protection, passphrase
  envelopes and rotation. The database is treated as an untrusted store.
  Legacy (unsigned) groups fall back to cooperative enforcement. See
  [devices.md](devices.md#how-access-is-enforced--read-this).
- Capture filters: OS "concealed" clipboard hints (password managers) are
  checked *before* reading; credential-looking text can be skipped; capture
  can be paused.

- Credentials live only in the OS credential store (`flutter_secure_storage`).
- Every log line passes through `redactSecrets`.
- E2E encryption keeps the database blind to content; the key scope binds the
  passphrase to one backend + URL.

### What a database holder can still see

Encryption covers `content`, and nothing else. Anyone with the credentials,
including the provider, sees, for every clip: the device id and name that
wrote it, the content type, the size in bytes, created/updated/deleted
timestamps, the key version, and the target device of a direct send. The whole
`devices` table (names, platforms, roles, public keys, presence) is plaintext
by design, because membership has to be verifiable without the passphrase.

`content_hash` is a *keyed* fingerprint on encrypted rows,
`HMAC-SHA256(HMAC-SHA256(key, "clipsync/content-hash/v1"), plaintext)`. A bare
SHA-256 of the plaintext, which is what earlier versions stored, let anyone
with read access confirm a guess or run a dictionary against short clips such
as one-time codes and passwords. Devices in the group still de-duplicate on
it; nobody else learns anything from it.

Rows written before either change are migrated from Settings → Privacy: clips
from the plaintext era can be cleared, and encrypted clips still carrying the
old plain digest can have it rewritten as the keyed one. A device can only
rewrite rows it wrote itself, since a clip's signature is verified against the
writing device's key.

Turning encryption on seals what is written next; it does not reach back over
history. Settings → Privacy counts the clips written before the group was
secured and offers to clear them; until that is done they stay readable.

Integrity and availability are a separate matter from confidentiality: a
holder of the credentials can still delete rows or add junk. Signatures mean
other devices will not *believe* forged clips or membership changes, but
nothing stops the writes themselves. Scope the database keys as tightly as
your backend allows.
- The repository refuses secrets at commit time (gitleaks + pre-commit) and in
  CI (full-history scan). All Actions are SHA-pinned.
