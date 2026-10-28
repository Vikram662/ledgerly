// Secure Razorpay boundary for the Thekedaar Android app.
const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8' };

export default {
  async fetch(request, env) {
    const cors = {
      'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
      'access-control-allow-headers':
        'authorization, content-type, x-razorpay-signature',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
    };
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }
    try {
      const path = new URL(request.url).pathname;
      let response;
      if (request.method === 'GET' && path === '/health') {
        response = ok({ service: 'thekedaar-subscription-api' });
      } else if (request.method === 'GET' && path === '/v1/app-config') {
        response = appConfig(env);
      } else if (request.method === 'POST' && path === '/v1/install') {
        response = await install(request, env);
      } else if (request.method === 'POST' && path === '/v1/login') {
        response = await login(request, env);
      } else if (request.method === 'POST' && path === '/v1/account/google') {
        response = await linkGoogle(request, env);
      } else if (request.method === 'POST' && path === '/v1/sync/push') {
        response = await syncPush(request, env);
      } else if (request.method === 'GET' && path === '/v1/sync/pull') {
        response = await syncPull(request, env);
      } else if (request.method === 'POST' && path === '/v1/notifications/token') {
        response = await updateNotificationToken(request, env);
      } else if (
        request.method === 'POST' &&
        path === '/v1/admin/complimentary-access'
      ) {
        response = await setComplimentaryAccess(request, env);
      } else if (request.method === 'POST' && path === '/v1/subscriptions') {
        response = await createSubscription(request, env);
      } else if (
        request.method === 'GET' &&
        path === '/v1/subscriptions/status'
      ) {
        response = await subscriptionStatus(request, env);
      } else if (
        request.method === 'POST' &&
        path === '/v1/subscriptions/link'
      ) {
        response = await linkSubscription(request, env);
      } else if (
        request.method === 'POST' &&
        path === '/v1/subscriptions/cancel'
      ) {
        response = await cancelSubscription(request, env);
      } else if (
        request.method === 'POST' &&
        path === '/v1/webhooks/razorpay'
      ) {
        response = await razorpayWebhook(request, env);
      } else {
        response = fail(404, 'not_found', 'Endpoint not found.');
      }
      addHeaders(response, cors);
      return response;
    } catch (error) {
      console.error(error);
      const response =
        error instanceof ApiError
          ? fail(error.status, error.code, error.message, error.details)
          : fail(500, 'internal_error', 'Something went wrong.');
      addHeaders(response, cors);
      return response;
    }
  },
};

async function install(request, env) {
  const body = await bodyJson(request);
  const installId = parseInstallId(body.installId);
  const name = requiredString(body.name, 'name', 120);
  const phone = optionalString(body.phone, 20);
  const userType = parseUserType(body.userType);
  const trades = optionalString(body.trades, 500);
  const fcmToken = optionalString(body.fcmToken, 4096);
  const googleIdToken = optionalString(body.googleIdToken, 4096);
  const google = googleIdToken ? await verifyGoogle(googleIdToken, env) : null;

  let row = await installRow(env, installId);
  if (google) {
    const owner = await env.DB.prepare(
      'SELECT * FROM installs WHERE google_sub = ?',
    )
      .bind(google.sub)
      .first();
    if (owner && owner.install_id !== installId) {
      throw accountExists(owner);
    }
    if (row?.google_sub && row.google_sub !== google.sub) {
      throw new ApiError(409, 'google_mismatch',
        'This phone is linked to another Google account.');
    }
  }
  // One account per mobile number: a reinstall logs in instead of
  // registering a second user.
  if (phone && digits(row?.phone) !== digits(phone)) {
    const owner = await phoneOwner(env, phone, installId);
    if (owner) throw accountExists(owner);
  }

  if (!row) {
    const customer = await razorpay(env, '/customers', 'POST', {
      name,
      ...(phone ? { contact: phone } : {}),
      fail_existing: '0',
      notes: { thekedaar_install_id: installId },
    });
    await env.DB.prepare(
      `INSERT INTO installs
       (install_id, account_id, customer_id, name, phone, user_type, trades,
        email, google_sub, fcm_token, platform, notification_updated_at,
        updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'android', ?, ?)`,
    )
      .bind(installId, installId, customer.id, name, phone, userType, trades,
        google?.email ?? null, google?.sub ?? null, fcmToken,
        fcmToken ? epoch() : null, epoch())
      .run();
  } else {
    if (
      (row.subscription_id || row.subscription_created_at) &&
      digits(row.phone) !== digits(phone)
    ) {
      throw new ApiError(
        409,
        'phone_change_requires_verification',
        'Phone change requires account verification.',
      );
    }
    await env.DB.prepare(
      `UPDATE installs SET name = ?, phone = ?, user_type = ?,
       trades = COALESCE(?, trades),
       email = COALESCE(?, email), google_sub = COALESCE(?, google_sub),
       fcm_token = COALESCE(?, fcm_token),
       notification_updated_at = CASE WHEN ? IS NULL
         THEN notification_updated_at ELSE ? END,
       updated_at = ? WHERE install_id = ?`,
    )
      .bind(name, phone, userType, trades, google?.email ?? null,
        google?.sub ?? null, fcmToken, fcmToken, epoch(), epoch(), installId)
      .run();
  }
  row = await installRow(env, installId);
  return ok(await session(row, env));
}

// A user who reinstalled or changed phones signs in with the Google account
// they registered with. The account moves to this install, keeping its
// Razorpay customer and subscription, so no duplicate user is created.
async function login(request, env) {
  const body = await bodyJson(request);
  const installId = parseInstallId(body.installId);
  const fcmToken = optionalString(body.fcmToken, 4096);
  const google = await verifyGoogle(
    requiredString(body.googleIdToken, 'googleIdToken', 4096),
    env,
  );
  const account = await env.DB.prepare(
    'SELECT * FROM installs WHERE google_sub = ?',
  )
    .bind(google.sub)
    .first();
  if (!account) {
    throw new ApiError(404, 'account_not_found',
      'No account is registered with this Google account.');
  }
  if (account.install_id !== installId) {
    const here = await installRow(env, installId);
    if (here) {
      if (here.subscription_id || here.subscription_created_at || here.google_sub) {
        throw new ApiError(409, 'install_in_use',
          'This phone already has another account.');
      }
      // A half-finished registration on this phone; the real account wins.
      await env.DB.prepare('DELETE FROM installs WHERE install_id = ?')
        .bind(installId)
        .run();
    }
    await env.DB.prepare(
      'UPDATE installs SET install_id = ?, updated_at = ? WHERE install_id = ?',
    )
      .bind(installId, epoch(), account.install_id)
      .run();
  }
  await env.DB.prepare(
    `UPDATE installs SET email = ?, fcm_token = COALESCE(?, fcm_token),
     updated_at = ? WHERE install_id = ?`,
  )
    .bind(google.email, fcmToken, epoch(), installId)
    .run();
  return ok(await session(await installRow(env, installId), env));
}

// Links a Google account to an already registered install, so a user who
// registered before Google login existed can log in on a new phone.
async function linkGoogle(request, env) {
  const user = await authenticated(request, env);
  const body = await bodyJson(request);
  const google = await verifyGoogle(
    requiredString(body.googleIdToken, 'googleIdToken', 4096),
    env,
  );
  const owner = await env.DB.prepare(
    'SELECT install_id FROM installs WHERE google_sub = ?',
  )
    .bind(google.sub)
    .first();
  if (owner && owner.install_id !== user.install_id) {
    throw new ApiError(409, 'google_in_use',
      'This Google account is already linked to another account.');
  }
  if (user.google_sub && user.google_sub !== google.sub) {
    throw new ApiError(409, 'google_mismatch',
      'This account is linked to another Google account.');
  }
  await env.DB.prepare(
    `UPDATE installs SET google_sub = ?, email = ?, updated_at = ?
     WHERE install_id = ?`,
  )
    .bind(google.sub, google.email, epoch(), user.install_id)
    .run();
  return ok({ email: google.email });
}

async function session(row, env) {
  return {
    token: await signToken(
      { sub: row.install_id, exp: epoch() + 90 * 86400 },
      env.APP_TOKEN_SECRET,
    ),
    customerId: row.customer_id,
    subscriptionId: row.subscription_id,
    status: row.subscription_status,
    user: {
      installId: row.install_id,
      name: row.name,
      phone: row.phone,
      userType: row.user_type,
      trades: row.trades,
      email: row.email,
    },
  };
}

function installRow(env, installId) {
  return env.DB.prepare('SELECT * FROM installs WHERE install_id = ?')
    .bind(installId)
    .first();
}

async function phoneOwner(env, phone, exceptInstallId) {
  const rows = await env.DB.prepare(
    'SELECT * FROM installs WHERE phone IS NOT NULL AND install_id != ?',
  )
    .bind(exceptInstallId)
    .all();
  return (rows.results || []).find((row) => digits(row.phone) === digits(phone));
}

function accountExists(owner) {
  return new ApiError(
    409,
    'account_exists',
    owner.google_sub
      ? 'You are already registered. Log in with your Google account.'
      : 'This mobile number is already registered.',
    { email: maskEmail(owner.email), canLogin: Boolean(owner.google_sub) },
  );
}

function maskEmail(email) {
  if (!email) return null;
  const [user, domain] = String(email).split('@');
  return `${user.slice(0, 2)}${'*'.repeat(Math.max(1, user.length - 2))}@${domain}`;
}

// Verifies a Google ID token issued to our OAuth web client (no OTP service
// needed: Google has already verified the email).
async function verifyGoogle(idToken, env) {
  if (!env.GOOGLE_CLIENT_ID) {
    throw new ApiError(503, 'google_not_configured',
      'Google login is not set up on the server.');
  }
  const response = await fetch(
    `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`,
  );
  const data = await response.json().catch(() => ({}));
  if (
    !response.ok ||
    data.aud !== env.GOOGLE_CLIENT_ID ||
    !['accounts.google.com', 'https://accounts.google.com'].includes(data.iss) ||
    String(data.email_verified) !== 'true' ||
    !data.sub ||
    Number(data.exp) < epoch()
  ) {
    throw new ApiError(401, 'invalid_google_login',
      'Google login could not be verified.');
  }
  return { sub: String(data.sub), email: String(data.email).toLowerCase() };
}

function parseInstallId(value) {
  const installId = requiredString(value, 'installId', 80);
  if (!/^[a-zA-Z0-9-]{16,80}$/.test(installId)) {
    throw new ApiError(400, 'invalid_install', 'Invalid install identifier.');
  }
  return installId;
}

function parseUserType(value) {
  const type = optionalString(value, 20) || 'contractor';
  if (!['contractor', 'shop', 'personal', 'lender'].includes(type)) {
    throw new ApiError(400, 'invalid_user_type', 'Invalid user type.');
  }
  return type;
}

// ─── Cloud sync of app data ─────────────────────────────────────────────────

// App tables copied to the cloud (lib/core/sync/sync_schema.dart).
const SYNC_TABLES = new Set([
  'business_profiles', 'roles', 'units', 'expense_categories', 'item_masters',
  'bill_templates', 'workers', 'wage_histories', 'holidays', 'clients', 'jobs',
  'attendances', 'settlements', 'piece_works', 'ledger_entries', 'documents',
  'document_lines', 'payments_received', 'expenses', 'suppliers',
  'supplier_ledger', 'task_reminders', 'audit_logs', 'loan_parties', 'loans',
  'loan_payments',
]);
const SYNC_PUSH_LIMIT = 200;
const SYNC_PULL_LIMIT = 500;
const SYNC_ROW_MAX_BYTES = 256 * 1024;

function accountId(user) {
  return user.account_id || user.install_id;
}

// Saves changed rows. Each row is keyed by its app UUID, so pushing the same
// row again (a retry, or after a Drive restore) updates it instead of adding
// a copy. The newer `at` wins; an older change only bumps `seq`, so the
// phone pulls the newer cloud version back.
async function syncPush(request, env) {
  const user = await authenticated(request, env);
  const account = accountId(user);
  const body = await bodyJson(request);
  const changes = Array.isArray(body.changes) ? body.changes : null;
  if (!changes || changes.length > SYNC_PUSH_LIMIT) {
    throw new ApiError(400, 'invalid_changes',
      `changes must be a list of at most ${SYNC_PUSH_LIMIT} rows.`);
  }
  const statement = env.DB.prepare(
    `INSERT INTO sync_rows
       (account_id, tbl, row_id, data, deleted, changed_at, seq)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6,
       (SELECT COALESCE(MAX(seq), 0) + 1 FROM sync_rows WHERE account_id = ?1))
     ON CONFLICT (account_id, tbl, row_id) DO UPDATE SET
       data = CASE WHEN excluded.changed_at >= sync_rows.changed_at
         THEN excluded.data ELSE sync_rows.data END,
       deleted = CASE WHEN excluded.changed_at >= sync_rows.changed_at
         THEN excluded.deleted ELSE sync_rows.deleted END,
       changed_at = MAX(excluded.changed_at, sync_rows.changed_at),
       seq = excluded.seq`,
  );
  const statements = changes.map((change) => {
    const { table, id, deleted, data, at } = parseSyncChange(change);
    return statement.bind(account, table, id, data, deleted ? 1 : 0, at);
  });
  if (statements.length) await env.DB.batch(statements);
  return ok({ account, saved: statements.length });
}

// Rows changed after `after` (a `seq` from an earlier pull), oldest first.
async function syncPull(request, env) {
  const user = await authenticated(request, env);
  const account = accountId(user);
  const url = new URL(request.url);
  const after = Number.parseInt(url.searchParams.get('after') || '0', 10);
  if (!Number.isSafeInteger(after) || after < 0) {
    throw new ApiError(400, 'invalid_cursor', 'after must be a sequence number.');
  }
  const result = await env.DB.prepare(
    `SELECT tbl, row_id, data, deleted, changed_at, seq FROM sync_rows
     WHERE account_id = ? AND seq > ? ORDER BY seq LIMIT ?`,
  )
    .bind(account, after, SYNC_PULL_LIMIT + 1)
    .all();
  const rows = result.results || [];
  const more = rows.length > SYNC_PULL_LIMIT;
  const page = rows.slice(0, SYNC_PULL_LIMIT);
  return ok({
    account,
    rows: page.map((row) => ({
      table: row.tbl,
      id: row.row_id,
      deleted: row.deleted === 1,
      data: row.data == null ? null : JSON.parse(row.data),
      at: row.changed_at,
      seq: row.seq,
    })),
    next: page.length ? page.at(-1).seq : after,
    more,
  });
}

function parseSyncChange(change) {
  if (!change || typeof change !== 'object') {
    throw new ApiError(400, 'invalid_change', 'Each change must be an object.');
  }
  const table = String(change.table || '');
  if (!SYNC_TABLES.has(table)) {
    throw new ApiError(400, 'invalid_table', `Unknown table ${table}.`);
  }
  const id = requiredString(change.id, 'id', 80);
  const at = Number(change.at);
  if (!Number.isSafeInteger(at) || at < 0) {
    throw new ApiError(400, 'invalid_change', 'at must be epoch milliseconds.');
  }
  const deleted = change.deleted === true;
  let data = null;
  if (!deleted) {
    if (!change.data || typeof change.data !== 'object' ||
        Array.isArray(change.data)) {
      throw new ApiError(400, 'invalid_change', 'data must be an object.');
    }
    data = JSON.stringify(change.data);
    if (data.length > SYNC_ROW_MAX_BYTES) {
      throw new ApiError(413, 'row_too_large', `Row ${table}/${id} is too large.`);
    }
  }
  return { table, id, deleted, data, at };
}

async function updateNotificationToken(request, env) {
  const user = await authenticated(request, env);
  const body = await bodyJson(request);
  const fcmToken = requiredString(body.fcmToken, 'fcmToken', 4096);
  await env.DB.prepare(
    `UPDATE installs SET fcm_token = ?, platform = 'android',
     notification_updated_at = ?, updated_at = ? WHERE install_id = ?`,
  )
    .bind(fcmToken, epoch(), epoch(), user.install_id)
    .run();
  return ok({ updated: true });
}

async function createSubscription(request, env) {
  const user = await authenticated(request, env);
  if (!digits(user.phone)) {
    throw new ApiError(
      400,
      'phone_required',
      'Add and verify a mobile number before starting a subscription.',
    );
  }
  if (
    user.subscription_id &&
    !['cancelled', 'expired', 'completed'].includes(user.subscription_status)
  ) {
    const current = await razorpay(
      env,
      `/subscriptions/${encodeURIComponent(user.subscription_id)}`,
    );
    return checkout(current, env);
  }
  // A trial is tied to customer history, not only this install ID.
  // This prevents reinstalling from granting another free trial.
  const trialEligible =
    !user.subscription_created_at && !(await hasUsedTrial(env, user));
  const subscription = await razorpay(env, '/subscriptions', 'POST', {
    plan_id: env.RAZORPAY_PLAN_ID,
    total_count: 120,
    quantity: 1,
    // Authorise the recurring mandate now; start paid billing after the trial.
    ...(trialEligible ? { start_at: epoch() + 5 * 86400 } : {}),
    customer_notify: 1,
    notes: { thekedaar_install_id: user.install_id, trial_days: '5' },
  });
  await env.DB.prepare(
    `UPDATE installs SET subscription_id = ?, subscription_status = ?,
     subscription_created_at = ?, updated_at = ? WHERE install_id = ?`,
  )
    .bind(
      subscription.id,
      subscription.status || 'created',
      subscription.created_at || epoch(),
      epoch(),
      user.install_id,
    )
    .run();
  return checkout(subscription, env, trialEligible);
}

async function subscriptionStatus(request, env) {
  const user = await authenticated(request, env);
  const complimentary = complimentaryPayload(user);
  if (complimentary) {
    const trialEligible =
      !user.subscription_created_at && !(await hasUsedTrial(env, user));
    return ok({
      ...complimentary,
      subscriptionId: user.subscription_id,
      trialEligible,
      accountEmail: user.email,
    });
  }
  if (!user.subscription_id) {
    const trialEligible =
      !user.subscription_created_at && !(await hasUsedTrial(env, user));
    return ok({
      status: 'none',
      active: false,
      trialEligible,
      accountEmail: user.email,
    });
  }
  const subscription = await razorpay(
    env,
    `/subscriptions/${encodeURIComponent(user.subscription_id)}`,
  );
  await updateSubscription(
    env,
    subscription.id,
    subscription.status,
    null,
    subscription.created_at,
  );
  return ok({
    ...statusPayload(subscription),
    trialEligible: false,
    accountEmail: user.email,
  });
}

async function hasUsedTrial(env, user) {
  const phone = digits(user.phone);
  if (!phone) return false;
  const result = await env.DB.prepare(
    `SELECT phone FROM installs
     WHERE phone IS NOT NULL AND subscription_created_at IS NOT NULL`,
  ).all();
  return (result.results || []).some((row) => digits(row.phone) === phone);
}
async function setComplimentaryAccess(request, env) {
  await adminAuthenticated(request, env);
  const body = await bodyJson(request);
  const installId = optionalString(body.installId, 80);
  const phone = optionalString(body.phone, 20);
  if (!installId && !phone) {
    throw new ApiError(400, 'missing_user', 'installId or phone is required.');
  }

  const mode = requiredString(body.mode, 'mode', 20);
  let until = null;
  if (mode === 'permanent') {
    until = -1;
  } else if (mode === 'until') {
    until = Number(body.expiresAt);
    if (!Number.isSafeInteger(until) || until <= epoch()) {
      throw new ApiError(400, 'invalid_expiry',
        'expiresAt must be a future Unix timestamp in seconds.');
    }
  } else if (mode !== 'revoke') {
    throw new ApiError(400, 'invalid_mode',
      'mode must be permanent, until, or revoke.');
  }

  const note = optionalString(body.note, 240);
  const value = mode === 'revoke' ? null : until;
  let changes = 0;
  if (installId) {
    const result = await env.DB.prepare(
      `UPDATE installs SET complimentary_until = ?, complimentary_note = ?,
       updated_at = ? WHERE install_id = ?`,
    )
      .bind(value, mode === 'revoke' ? null : note, epoch(), installId)
      .run();
    changes = result.meta?.changes || 0;
  } else {
    const rows = await env.DB.prepare(
      'SELECT install_id, phone FROM installs WHERE phone IS NOT NULL',
    ).all();
    for (const row of rows.results || []) {
      if (digits(row.phone) !== digits(phone)) continue;
      const result = await env.DB.prepare(
        `UPDATE installs SET complimentary_until = ?, complimentary_note = ?,
         updated_at = ? WHERE install_id = ?`,
      )
        .bind(value, mode === 'revoke' ? null : note, epoch(), row.install_id)
        .run();
      changes += result.meta?.changes || 0;
    }
  }
  if (!changes) {
    throw new ApiError(404, 'user_not_found', 'No registered user matched.');
  }
  return ok({
    updated: changes,
    mode,
    expiresAt: until === -1 ? null : until,
  });
}

function complimentaryPayload(user) {
  const until = Number(user.complimentary_until);
  if (until !== -1 && (!Number.isSafeInteger(until) || until <= epoch())) {
    return null;
  }
  return {
    status: 'active',
    active: true,
    accessSource: 'complimentary',
    complimentaryPermanent: until === -1,
    complimentaryExpiresAt: until === -1 ? null : until,
  };
}

async function linkSubscription(request, env) {
  const user = await authenticated(request, env);
  const body = await bodyJson(request);
  const subscriptionId = requiredString(
    body.subscriptionId,
    'subscriptionId',
    80,
  );
  if (!/^sub_[a-zA-Z0-9]+$/.test(subscriptionId)) {
    throw new ApiError(400, 'invalid_subscription', 'Invalid subscription ID.');
  }
  const subscription = await razorpay(
    env,
    `/subscriptions/${encodeURIComponent(subscriptionId)}`,
  );
  if (!subscription.customer_id || !user.phone) {
    throw new ApiError(
      403,
      'cannot_verify_owner',
      'Subscription ownership could not be verified.',
    );
  }
  const customer = await razorpay(
    env,
    `/customers/${encodeURIComponent(subscription.customer_id)}`,
  );
  if (digits(customer.contact) !== digits(user.phone)) {
    throw new ApiError(
      403,
      'owner_mismatch',
      'This subscription belongs to another mobile number.',
    );
  }
  await env.DB.prepare(
    `UPDATE installs SET subscription_id = ?, subscription_status = ?,
     subscription_created_at = ?, updated_at = ? WHERE install_id = ?`,
  )
    .bind(
      subscription.id,
      subscription.status,
      subscription.created_at || epoch(),
      epoch(),
      user.install_id,
    )
    .run();
  return ok(statusPayload(subscription));
}

async function cancelSubscription(request, env) {
  const user = await authenticated(request, env);
  if (!user.subscription_id) {
    throw new ApiError(409, 'no_subscription', 'No subscription is linked.');
  }
  const subscription = await razorpay(
    env,
    `/subscriptions/${encodeURIComponent(user.subscription_id)}/cancel`,
    'POST',
    { cancel_at_cycle_end: 0 },
  );
  await updateSubscription(
    env,
    subscription.id,
    subscription.status || 'cancelled',
  );

  return ok({ ...statusPayload(subscription), trialEligible: false });
}

async function razorpayWebhook(request, env) {
  const raw = await request.text();
  const signature = request.headers.get('x-razorpay-signature') || '';
  if (!await verifyHmac(raw, signature, env.RAZORPAY_WEBHOOK_SECRET)) {
    throw new ApiError(401, 'invalid_signature', 'Invalid webhook signature.');
  }
  const event = JSON.parse(raw);
  const subscription = event.payload?.subscription?.entity;
  const payment = event.payload?.payment?.entity;
  const subscriptionId = subscription?.id || payment?.subscription_id;
  if (subscriptionId) {
    await updateSubscription(
      env,
      subscriptionId,
      subscription?.status || statusFromEvent(event.event),
      payment?.id || null,
      subscription?.created_at,
    );
  }
  return ok({ received: true });
}

function checkout(subscription, env, trialEligible = false) {
  return ok({
    keyId: env.RAZORPAY_KEY_ID,
    subscriptionId: subscription.id,
    status: subscription.status,
    trialEndsAt: subscription.start_at || null,
    trialEligible,
  });
}

function statusPayload(subscription) {
  const status = subscription.status || 'unknown';
  return {
    subscriptionId: subscription.id,
    status,
    active: ['active', 'authenticated'].includes(status),
    currentEnd: subscription.current_end || null,
    trialEndsAt: subscription.start_at || null,
  };
}

function appConfig(env) {
  const latestBuild = positiveInteger(env.APP_LATEST_BUILD, 1);
  const minimumBuild = positiveInteger(env.APP_MINIMUM_BUILD, 1);
  return ok({
    latestBuild,
    minimumBuild: Math.min(minimumBuild, latestBuild),
    updateUrl: env.APP_UPDATE_URL || '',
    message: env.APP_UPDATE_MESSAGE ||
      'Thekedaar ka naya version available hai. Abhi update karein.',
  });
}

function positiveInteger(value, fallback) {
  const parsed = Number.parseInt(String(value || ''), 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

async function updateSubscription(
  env,
  id,
  status,
  paymentId = null,
  createdAt = null,
) {
  const sets = ['subscription_status = ?', 'updated_at = ?'];
  const values = [status || 'unknown', epoch()];
  if (paymentId) {
    sets.push('latest_payment_id = ?');
    values.push(paymentId);
  }
  if (createdAt) {
    sets.push(
      'subscription_created_at = COALESCE(subscription_created_at, ?)',
    );
    values.push(createdAt);
  }
  values.push(id);
  await env.DB.prepare(
    `UPDATE installs SET ${sets.join(', ')} WHERE subscription_id = ?`,
  )
    .bind(...values)
    .run();
}

async function authenticated(request, env) {
  const header = request.headers.get('authorization') || '';
  if (!header.startsWith('Bearer ')) {
    throw new ApiError(401, 'unauthorized', 'Installation is not registered.');
  }
  const token = await verifyToken(header.slice(7), env.APP_TOKEN_SECRET);
  if (!token || token.exp < epoch()) {
    throw new ApiError(401, 'token_expired', 'Session expired.');
  }
  const row = await env.DB.prepare(
    'SELECT * FROM installs WHERE install_id = ?',
  )
    .bind(token.sub)
    .first();
  if (!row) {
    throw new ApiError(401, 'unknown_install', 'Installation was not found.');
  }
  return row;
}

async function adminAuthenticated(request, env) {
  const header = request.headers.get('authorization') || '';
  const expected = `Bearer ${env.ADMIN_API_SECRET || ''}`;
  if (!env.ADMIN_API_SECRET || !safeEqual(header, expected)) {
    throw new ApiError(401, 'unauthorized', 'Admin authorization failed.');
  }
}

async function razorpay(env, path, method = 'GET', body) {
  const response = await fetch(`https://api.razorpay.com/v1${path}`, {
    method,
    headers: {
      authorization: `Basic ${btoa(
        `${env.RAZORPAY_KEY_ID}:${env.RAZORPAY_KEY_SECRET}`,
      )}`,
      'content-type': 'application/json',
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error('Razorpay API error', response.status, data?.error?.code);
    throw new ApiError(
      502,
      'payment_provider_error',
      data?.error?.description || 'Payment provider request failed.',
    );
  }
  return data;
}

async function signToken(payload, secret) {
  const encoded = base64url(JSON.stringify(payload));
  return `${encoded}.${await hmac(encoded, secret)}`;
}

async function verifyToken(token, secret) {
  const [payload, signature, extra] = token.split('.');
  if (
    !payload ||
    !signature ||
    extra ||
    !safeEqual(await hmac(payload, secret), signature)
  ) {
    return null;
  }
  try {
    return JSON.parse(fromBase64url(payload));
  } catch (_) {
    return null;
  }
}

async function verifyHmac(value, signature, secret) {
  return signature.length > 0 && safeEqual(await hmac(value, secret), signature);
}

async function hmac(value, secret) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value)),
  );
  return [...bytes]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function base64url(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

function fromBase64url(value) {
  const padded =
    value.replaceAll('-', '+').replaceAll('_', '/') +
    '='.repeat((4 - (value.length % 4)) % 4);
  const binary = atob(padded);
  return new TextDecoder().decode(
    Uint8Array.from(binary, (character) => character.charCodeAt(0)),
  );
}

function safeEqual(left, right) {
  if (left.length !== right.length) return false;
  let result = 0;
  for (let index = 0; index < left.length; index++) {
    result |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return result === 0;
}

function statusFromEvent(event) {
  const value = String(event || '').split('.').at(-1);
  return value === 'charged' ? 'active' : value || 'unknown';
}

function digits(value) {
  return String(value || '')
    .replace(/\D/g, '')
    .slice(-10);
}

function epoch() {
  return Math.floor(Date.now() / 1000);
}

async function bodyJson(request) {
  try {
    return await request.json();
  } catch (_) {
    throw new ApiError(400, 'invalid_json', 'Request body must be valid JSON.');
  }
}

function requiredString(value, field, maxLength) {
  if (
    typeof value !== 'string' ||
    !value.trim() ||
    value.trim().length > maxLength
  ) {
    throw new ApiError(400, 'invalid_request', `${field} is required.`);
  }
  return value.trim();
}

function optionalString(value, maxLength) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || value.trim().length > maxLength) {
    throw new ApiError(400, 'invalid_request', 'Invalid text value.');
  }
  return value.trim();
}

function addHeaders(response, headers) {
  for (const [key, value] of Object.entries(headers)) {
    response.headers.set(key, value);
  }
}

function ok(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: JSON_HEADERS,
  });
}

function fail(status, code, message, details = null) {
  return new Response(JSON.stringify({ error: { code, message, ...details } }), {
    status,
    headers: JSON_HEADERS,
  });
}

class ApiError extends Error {
  constructor(status, code, message, details = null) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}
