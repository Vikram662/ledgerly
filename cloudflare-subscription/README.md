# Thekedaar Subscription API

Secure Cloudflare Worker boundary between the Flutter app and Razorpay. Business
records never pass through this service; it stores only payment identifiers and
subscription state.

## Deploy

1. Create D1 database `thekedaar-subscriptions` and paste its database ID in
   `wrangler.jsonc`.
2. `npm install`
3. `npx wrangler login`
4. `npm run db:remote`
5. Add encrypted secrets (never commit or paste them into chat):

   ```text
   npx wrangler secret put RAZORPAY_KEY_ID
   npx wrangler secret put RAZORPAY_KEY_SECRET
   npx wrangler secret put RAZORPAY_PLAN_ID
   npx wrangler secret put RAZORPAY_WEBHOOK_SECRET
   npx wrangler secret put APP_TOKEN_SECRET
   npx wrangler secret put ADMIN_API_SECRET
   ```

6. `npm run deploy`
7. Razorpay webhook URL: `https://<worker>.workers.dev/v1/webhooks/razorpay`
   Enable subscription authenticated/activated/charged/pending/halted/cancelled
   and payment captured/failed events. Use the same webhook secret.

Use Razorpay Test Mode keys first. Configure the Flutter build with
`--dart-define=SUBSCRIPTION_API_URL=https://<worker>.workers.dev`.

## Complimentary access (owner/admin)

This protected endpoint gives one registered user permanent free access or
access until a fixed time. Other users and paid Razorpay subscriptions keep the
existing flow. Keep `ADMIN_API_SECRET` only in Cloudflare and your admin tools;
never put it in the app or source code.

Send `Authorization: Bearer <ADMIN_API_SECRET>` to
`POST /v1/admin/complimentary-access`. Identify the user by exact registered
phone number or by `installId`.

Permanent access:

```json
{"phone":"+919876543210","mode":"permanent","note":"Owner grant"}
```

Time-limited access (`expiresAt` is a future Unix timestamp in seconds):

```json
{"phone":"+919876543210","mode":"until","expiresAt":1798761599,"note":"Free through 31 Dec 2026"}
```

Remove only the free grant (the paid subscription is left untouched):

```json
{"phone":"+919876543210","mode":"revoke"}
```

The app picks up the change when it reopens or refreshes Manage Subscription.
When a timed grant expires, status automatically falls back to the user's
normal Razorpay status; no cleanup job is needed.

## Trigger the app update popup

Set these Worker variables in `wrangler.jsonc` and deploy:

- `APP_LATEST_BUILD`: newest published Flutter build number. If it is greater
  than `AppConfig.appBuildNumber`, the popup appears.
- `APP_MINIMUM_BUILD`: oldest allowed build. A lower installed build makes the
  popup mandatory; otherwise users can choose **Baad mein**.
- `APP_UPDATE_URL`: Play Store or APK download page.
- `APP_UPDATE_MESSAGE`: text displayed in the popup.

For every release, increment both `version: ...+N` in `pubspec.yaml` and
`AppConfig.appBuildNumber`, publish the app, then raise `APP_LATEST_BUILD`.
