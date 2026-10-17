# Devices, pairing and access control

Nija has no server: every device talks to *your* database with the
credentials you gave it. This page explains how devices join a sync group,
what "block", "remove", roles and expiry actually do, and where the limits
of that model are.

## Pairing a new device

1. On a device that already syncs: **Settings → Devices → Add a device**.
   Choose the role and access duration for the new device, then
   **Show pairing code**.
2. On the new device: **Settings → Devices → Join another group** (or
   *Already set up? Join with a code* on the welcome screen). Scan the QR
   code (phones) or paste the copied code (desktops), then type the
   8-digit PIN shown next to the code.
3. Review what the code grants and tap **Join**. If the group uses
   end-to-end encryption and the host did not include the passphrase, type
   it now.

What travels inside the code: the database type and settings (including the
secret fields), a device id **and identity keys** chosen by the host, the
admin public key to pin, the role and expiry, the host's name, and, only
with *Can manage devices*, the admin key. The encryption passphrase never
travels in the code: with *Share encryption passphrase* on, the host seals it
to the new device's key inside its device row.

### How the code is protected

The code is the settings JSON encrypted with AES-256-GCM under a key derived
from the PIN with Argon2id (64 MiB, 3 iterations), salted per code. The wire
form is `NIJA1.` + base64url. Without the PIN a photo of the QR is an
offline brute-force of 10⁸ PINs at roughly a second each. The host keeps a
code valid for 5 minutes; the joining device refuses stale codes.

Rules the app follows around codes:

- The pairing code is copied to the clipboard **without** being recorded in
  history, and a pairing code that appears on any device's clipboard is never
  captured, so credentials cannot leak into the shared history.
- The passphrase is delivered sealed to the new device only when you switch
  *Share encryption passphrase* on; otherwise it is typed on the new device.
- Treat the code like the database password it contains: show it only to the
  device you are adding, never share screenshots.

### What the host does when you generate a code

It generates the new device's keys, writes a *pending* row to the `devices`
table with the id, public keys, role, expiry, `paired_by` (and, in a signed
group, the admin signature and sealed passphrase). The list shows it as **Invited · waiting**.
When the joining device first checks in, it adopts that id and inherits the
row: the host decided the access, not the joiner. If the code is never used,
**Cancel invitation** (on the code screen) or **Forget** (in the list)
deletes the row.

## Managing devices

**Settings → Devices → Manage devices** lists every device row, with
presence (online / last seen, platform, app version) and its membership.

| Action | Effect |
|---|---|
| **Pause sync** | The device stays paired but sends and receives nothing from its next check-in (about a minute). Clips copied elsewhere while it is paused never reach it (nor those written in the minute or so before it noticed the pause), and what it copies meanwhile stays on it; its deletions and *Send to* clips still go out on resume. **Resume** brings it back. Paused devices still receive rotated passphrases. Cooperative like every status: a device on 0.4.2 or older reads `paused` as active and keeps syncing. |
| **Block** | Other devices ignore its clips. The device stops syncing on its next check-in (about a minute), deletes its copy of the credentials and passphrase, and shows a notice. **Unblock** clears the status, but the device has to be paired again. |
| **Change role** | *Send & receive* (default), *Send only* (pushes its clips, never pulls history, like a guest laptop), *Receive only* (pulls, never pushes, like a display machine). Applied on the device's next check-in. |
| **Access duration** | Sets `expires_at`. When it passes, the device disconnects itself the same way as a block, and other devices stop applying its clips. |
| **Remove** | Like block, but permanent: the row stays as a tombstone so the device learns it was removed. |
| **Forget** | Deletes the row. Use after the device has disconnected (or for unused invitations). A device that is still running notices the missing row and disconnects with "removed". |

A device cannot manage itself; rename it under **This device**.

### Permissions and more admins

In a signed group the admin can hand out powers from a device's menu:

- **Permissions…** grants a member one power without making it an admin.
  Today that is *Delete database history* (Settings → Data). The grant is
  stored in the device row as `permissions` and covered by the admin
  signature, so a member cannot grant it to itself: editing the field breaks
  the signature and every device then distrusts the row. Taking it back
  works the same way.
- **Make admin…** seals the group admin key to the device's X25519 key and
  stores it as `admin_envelope`, also signed. On its next check-in the
  device opens it, checks it matches the pinned admin key, and from then on
  can do everything the admin can. **There is no undo**: the device keeps
  the key even after it is removed. Taking admin power back means securing
  the group again with a new admin key.

Both need the 0.5 schema upgrade on Supabase and PocketBase (two text
columns, see each backend's page). Without it the app writes the grant,
reads it back, finds it missing, restores the previous signed row and
reports the upgrade to run, so a device is never left with a broken
signature. CouchDB, Firestore and MongoDB need nothing.

### Leaving a group, or starting a new one

- **Settings → Devices → Leave this group** deletes this device's row,
  forgets the database credentials, passphrase and admin key, and goes back
  to local-only. History stays unless you tick *Also delete history on this
  device*. If this is the only admin, make another device an admin first or
  nobody can manage the group afterwards.
- **Settings → Devices → Start a new group on this database** deletes every
  clip and device row and makes this device the admin of a new group, with a
  new admin key and a new passphrase. The other devices disconnect on their
  next check-in; pair them again. Because it needs only the database
  credentials, this is also the way back when the admin device is lost (for
  example, its keychain was wiped by a reinstall).

### Resetting the database

Dropping the tables (or deleting every device row) and creating them again
is treated as a fresh database, not as every device being forgotten: a
device whose row is gone disconnects only when one of the remaining rows
belongs to a device it already knew (being forgotten always leaves at least
the row of the device that did it). Otherwise it registers again, even when
other devices got back first. The
admin signs its own row again on its first check-in. In a signed group the
other devices then show as unverified, because their rows are new and
unsigned; pair them again from the admin. History already on each device
stays there and is not uploaded again.

Keep every admin device on 0.5 or later. An older admin rewrites whole
device rows without these fields, which drops a grant (the device then
simply loses it; nothing is granted by accident).

### Deleting clips

- **A single clip** can be deleted from the group only by the device that
  copied it: the deletion is signed with that device's key, and other devices
  verify it against the same key. On any other device, *Delete on this
  device* removes the local copy only.
- **Settings → Data → Delete history on this device** removes every local
  clip. The database keeps its copy, and those clips are not downloaded again.
- **Settings → Data → Delete history in the database** removes every clip and
  deletion record from the database. Device rows and keys stay, so sync
  carries on, and each device keeps the history it already has. In a signed
  group only the admin, or a member it gave the permission, sees this
  enabled. Anyone holding the database credentials can still delete rows
  directly; this, like the rest of membership, is enforced by the app, not
  by the database.
- **Settings → Sync → Sync with the database** turns sync off on one device.
  Capture continues locally and nothing copied while it is off is sent.

### Send to one device

From the history menu, **Send to…** pushes a copy of a clip addressed to a
single device (`target_device_id`). Every other device skips it on pull. The
copy is hidden in the sender's history; the receiver sees it with a
"sent only to this device" mark.

## How access is enforced: read this

All devices in a group hold the **same** database credentials, so the
database itself cannot tell them apart. Nija therefore enforces
membership cryptographically, on every device, instead of relying on the
database:

### Signed groups (the default for groups created with 0.2+)

Choosing a database with *Encrypt and sign this group* on (the default)
generates a random passphrase, turns on end-to-end encryption and makes that
device the admin in one step. Nothing has to be typed on other devices: they
receive the passphrase sealed through pairing. *Settings → Privacy → Show
passphrase* reveals it if a device must join by typing the database
credentials instead.

- Every device has an **identity**: an Ed25519 signing key and an X25519
  key. The private halves live only in the OS credential store.
- The group has an **admin key**. The device that pressed *Secure this
  group* (or created the group) holds it; every other device pins its
  public key when it joins through a pairing code, or after confirming the
  fingerprint once (legacy members).
- **Every clip is signed** by the device that captured it, over the stored
  form (ciphertext when encrypted). Receivers verify the signature against
  the signing key on that device's admin-signed row before decrypting or
  applying anything.
- **Every membership change is signed by the admin key**: status, role,
  expiry, the device's public keys, the admin flag, the key envelope and a
  monotonically increasing version. Devices honour a row only if the
  signature verifies and the version is not lower than one they have seen.
- **Passphrases travel in envelopes**, sealed to each device's X25519 key
  and covered by the admin signature. *Rotate encryption key* issues a fresh
  random passphrase to every verified active or paused device; a removed or blocked
  device gets nothing and cannot read clips sealed with the new key. The
  admin device does the same on its own when a member turns out to hold a
  different key (its row carries a newer key version than the admin has, or
  its clips at the admin's version do not open), so devices never have to
  compare fingerprints to get back in step.

With that in place, someone who has the database credentials but not the
admin key can still *read the database* (ciphertext only, when encryption is
on) and *delete rows*, but cannot:

| Attack | Outcome |
|---|---|
| Inject a clip as one of your devices (unsigned, wrong key, or a genuine clip with content / target / timestamp changed) | Rejected: the signature does not verify |
| Replay an old signed version of a clip (e.g. to undelete it) | Ignored: last-writer-wins keeps the newer tombstone |
| Register a new device and start sending | Its row is not admin-signed → shown as **Unverified**, its clips are dropped by everyone |
| Block, remove or expire a device by editing its row | Ignored: the signature breaks. The device keeps running; the admin re-signs the true state |
| Sign such a change with their own admin key | Ignored: only the pinned admin key counts |
| Un-block themselves after a genuine block | Editing the row breaks the signature → still untrusted; restoring the earlier valid row is a rollback (lower version) → still untrusted |
| Give themselves the admin flag or a wider role | Same: unsigned change → untrusted |
| Swap a device's key envelope for one holding a passphrase they chose | Ignored: the envelope is covered by the admin signature |
| Keep an old copy of the app running after removal to read new clips | Rotate the key: they never receive the new version |
| Pose as an existing device from a second machine (cloned id) | They lack the private signing key → nothing they send verifies |
| Read clips that were sent to one specific device | Same as any other clip: needs the group key; targeted delivery is a routing hint, encryption is the secrecy |

What the model does **not** cover:

- The **admin key** is the root of trust. Losing the admin device means
  setting the group up again; an attacker who obtains it controls
  membership. The pairing option *Can manage devices* copies it to another
  device: use deliberately.
- **Trust on first use**: a member of a legacy group that sees a new admin
  key is asked to compare the fingerprint with the admin device. Accepting
  a fingerprint you did not check hands the group to whoever wrote that row.
- **Deletion and denial of service**: database credentials still allow
  deleting or overwriting rows. Signatures make tampering detectable, not
  impossible. Use the backend's own access rules to limit that.
- **Plaintext when encryption is off**: without a passphrase the database
  (and anyone with its credentials) reads every clip. Turn encryption on.
- **A pairing code plus its PIN** is a full invitation: the device it
  creates is admin-signed. Cancel unused invitations and rotate the key if
  a code may have leaked.

### Legacy groups (created with 0.1, or not yet secured)

Nothing is signed. Block / remove / expiry are honoured cooperatively by
each app, devices that publish a signing key still get their clips
verified, but anyone with the credentials can pose as a device, undo a
block, or read unencrypted clips. **Settings → Devices → Secure this
group** upgrades in place: the device becomes admin, signs every current
member, and other devices confirm the fingerprint once.

App versions before 0.2 never read `status`, never sign, and are shown as
*Unverified* in a signed group; their clips are dropped. Update them and
re-add them with a pairing code.

## Upgrading a database created with 0.1.0

`devices` gained membership, key and signature columns; `clip_items`
gained `target_device_id`, `key_version` and `sig`. Schema-less backends
(CouchDB, Firestore, MongoDB) need nothing. Supabase and PocketBase need
the upgrade snippet in their guide; **Test connection & schema** reports
what is missing, and PocketBase refuses to sync until the fields exist
because it silently drops unknown ones.

## Schema reference

`devices` row:

| field | written by | covered by admin signature |
|---|---|---|
| `id` | the device (heartbeat) or the host (invitation) | yes |
| `name`, `platform`, `last_seen`, `app_version` | the device, every heartbeat | no |
| `sign_pub`, `box_pub` | host at invitation (signed group) or the device itself once (legacy) | yes |
| `status`, `role`, `expires_at` | admin | yes |
| `paired_by` | host at invitation | no |
| `admin`, `admin_pub` | admin | yes |
| `membership_version`, `membership_sig` | admin | version yes; sig is the signature |
| `key_version`, `key_envelope` | admin (invite / rotate) | yes |

`clip_items` gained `target_device_id` (routing), `key_version` (which
passphrase sealed it) and `sig` (Ed25519 over the stored row).

A heartbeat writes only presence fields, so it never undoes a block or
breaks a signature.
