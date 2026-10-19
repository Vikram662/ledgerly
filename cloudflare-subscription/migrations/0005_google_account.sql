-- One account per person: a verified Google account (no OTP service) lets
-- the same user log in on a new phone instead of registering again.
ALTER TABLE installs ADD COLUMN email TEXT;
ALTER TABLE installs ADD COLUMN google_sub TEXT;
ALTER TABLE installs ADD COLUMN trades TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS installs_google_sub_idx
  ON installs(google_sub);
