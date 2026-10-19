# Ledgerly (Thekedaar)

Flutter app (`lib/`) plus a Cloudflare Worker for subscriptions and accounts
(`cloudflare-subscription/`).

- Do not install the Flutter or Android SDK on this machine (no disk space).
  Builds and tests run only on GitHub CI (`.github/workflows/build.yml`).
- Shared UI lives in `lib/core/widgets/` (`AppBadge`, `AppChip`, `PhoneField`,
  `NoteDateField`, `AmountPadFooter`, ...). Reuse these; do not hand-build
  badges, chips or phone fields on a screen.

## Deploy the subscription worker

Run from `cloudflare-subscription/`. Wrangler is a dev dependency
(`npm ci` installs it).

```bash
cd cloudflare-subscription
npm ci                      # once, installs wrangler
npx wrangler login          # once, opens the browser to sign in to Cloudflare
npx wrangler whoami         # check the right Cloudflare account

# 1. Database migrations (adds email / google_sub / trades in 0005)
npm run db:remote

# 2. Google login: the Web OAuth client id, same value as the
#    GOOGLE_SERVER_CLIENT_ID GitHub secret (xxx.apps.googleusercontent.com)
npx wrangler secret put GOOGLE_CLIENT_ID

# 3. Deploy
npm run deploy
```

Check after deploy (`<worker>` is the URL `npm run deploy` prints):

```bash
curl https://<worker>.workers.dev/health
```

It should answer `{"service":"thekedaar-subscription-api"}`. Then on a phone:
uninstall the app, install again, tap **Already registered? Log in** and sign
in with the same Google account. The plan should come back without a new
registration.

Existing secrets (`RAZORPAY_*`, `APP_TOKEN_SECRET`, `ADMIN_API_SECRET`) are
already set and do not need to be entered again. See
`cloudflare-subscription/README.md` for details.
