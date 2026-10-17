# Android package migration: com.ledgerly.app

The Android application ID is now `com.ledgerly.app`. Android and Google Play
treat this as a new app. It cannot update an installed
`com.thekedaar.thekedaar` app, and local app data does not move automatically.

The database filename `thekedaar.sqlite`, Drive folder `Thekedaar Backups`,
Dart package name, Firebase project ID, and subscription API hostname stay
unchanged so existing data and services remain discoverable.

## Firebase and Google Cloud

1. Open Firebase Console > project `thekedaar-ff80c` > Project settings.
2. Add a new Android app with package name `com.ledgerly.app`.
3. Add SHA-1 and SHA-256 for every signing key used:
   - the upload/release keystore used by GitHub Actions;
   - debug SHA fingerprints only if local debug sign-in is needed.
4. Download the new `google-services.json`. Confirm its
   `client_info.android_client_info.package_name` is `com.ledgerly.app`.
5. Copy the new `mobilesdk_app_id` from that file into the Android `appId`
   in `lib/firebase_options.dart`. Ask the maintainer to make this source change;
   do not commit the full JSON file.
6. Base64-encode that entire file and replace the GitHub Actions repository
   secret `GOOGLE_SERVICES_JSON_BASE64`.
7. In Google Cloud Console > APIs & Services > Credentials, verify an Android
   OAuth client exists for `com.ledgerly.app` and the release SHA-1. Create
   it if Firebase did not create it.
8. Keep the Web OAuth client used by `GOOGLE_SERVER_CLIENT_ID`. Change that
   GitHub secret only if a new Web client is deliberately created.
9. Keep Google Drive API enabled and keep the OAuth consent-screen test or
   production users configured.

Firebase project ID and GCP project name do not need to be renamed. Renaming the
display name is optional and does not affect the app connection.

## GitHub Actions secrets

Repository Settings > Secrets and variables > Actions must contain:

- `GOOGLE_SERVICES_JSON_BASE64`: new Firebase file for
  `com.ledgerly.app`.
- `GOOGLE_SERVER_CLIENT_ID`: Web OAuth client ID for Drive sign-in.
- `SUBSCRIPTION_API_URL`: unchanged deployed Worker URL.
- Android signing secrets: unchanged when the same release key is retained.

Do not commit `google-services.json` or signing files.

## Google Play

A package ID cannot be changed for an existing Play listing. Create a new Play
Console app, upload the Ledgerly AAB built with `com.ledgerly.app`, and
configure its store listing, privacy policy, Data safety, app access, countries,
and testing/production tracks. Keep the same release signing key where possible.

The subscription Worker update URL has been changed to the new Play package.
Deploy the Worker after the new Play listing exists:

`cd cloudflare-subscription`
`npm run deploy`

The Worker service name, API URL, D1 database, and subscription records remain
unchanged.

## Existing users and data

The old and new package IDs have separate Android storage. Before switching,
users should create a Google Drive backup in the old app. They can then install
the new app and restore that backup. Do not rename `thekedaar.sqlite` or
`Thekedaar Backups`.

## GitHub repository rename

Repository rename is independent from the Android package ID.

1. GitHub repository > Settings > General > Repository name > enter the new name.
2. Update the local remote, for example:
   `git remote set-url origin https://github.com/Vikram662/Ledgerly.git`
3. Verify Actions, Pages, branch protection, webhooks and external deployment
   integrations after the rename.
4. GitHub normally redirects the old repository URL, but update README links,
   badges, clones and deployment references to the new URL.
5. Actions secrets normally remain with the renamed repository; verify them
   before the next release build.
