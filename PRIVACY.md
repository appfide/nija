# Nija privacy policy

Last updated: 18 October 2026

Nija is a clipboard manager made by Appfide Private Limited, XXI/152 Panadans,
Cochin University Post, Ernakulam 682022, Kerala, India ("we"). This policy
covers the Nija apps for macOS, iOS, iPadOS, Windows, Linux and Android,
whether installed from the App Store or from GitHub.

## The short version

**Your clipboard stays in your own database, not on anyone else's server.**
We run no Nija server and have no Nija accounts. We collect nothing, we see
nothing you copy, and there is no analytics, advertising or tracking in the
app.

## What the app stores, and where

| What | Where it goes | Who can read it |
|---|---|---|
| Your clipboard history | A local database on the device | You, on that device |
| The same history, if you turn on sync | The database **you** choose and connect (Supabase, PocketBase, CouchDB, Firebase Firestore or MongoDB), directly from your device | You, and whoever runs that database. With end-to-end encryption on (the default for a new group), the database only stores ciphertext it cannot read |
| Database credentials, encryption keys, device keys | The operating system's credential store (Keychain, Keystore, Credential Manager or Secret Service) | The app on that device |
| Settings | The app's preferences on the device | The app on that device |

The database you connect is run by you or by a provider you picked. Its own
terms and privacy policy apply to what it stores; we have no access to it and
are not a party to that relationship. With end-to-end encryption the provider
still sees clip sizes, timestamps and device names, as explained in
[docs/architecture.md](docs/architecture.md).

## Network connections the app makes

- **Your database**, using the address and credentials you enter. Nothing else
  is sent there besides your clips and your devices' records.
- **github.com**, only when you open *About → Get it on your other devices*,
  to list the latest release. No identifier is sent.
- **api.supabase.com**, only if you choose *Set up automatically* for a
  Supabase database, with the access token you paste for that one request.
  The token is not stored.

The app makes no other connections.

## Permissions

- **Clipboard**: read to record your history. On iPhone, iPad and Android the
  app reads it only while it is open or when you tap *Capture*. Content that
  password managers mark as concealed is not recorded, and you can skip
  anything that looks like a key or token, or pause recording.
- **Camera** (iPhone, iPad, Android): only to scan a pairing or admin QR code
  shown by one of your other devices. Images never leave the device.
- **Local network**: only if your database runs on your local network.

## Your control over your data

Everything is under your control in the app: delete one clip everywhere,
delete this device's history, delete the database history for the whole
group, turn off sync on one device, or remove a device and its clips. Deleting
the app deletes its local data. Data in your own database is yours to delete
with that database's tools as well.

Because we hold no personal data about you, we have nothing to give out,
correct or erase on request; requests about data in your database go to
whoever runs it, which is usually you.

## Children

Nija is a general productivity tool and is not directed at children.

## Changes

We publish changes to this policy in this file in the
[Nija repository](https://github.com/appfide/nija), where its full history is
public.

## Contact

Questions: dhipin@appfide.com, or open an issue at
https://github.com/appfide/nija/issues.
