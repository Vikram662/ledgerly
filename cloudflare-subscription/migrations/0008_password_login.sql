-- Email + password login, for when Google sign-in is not available
-- (unverified OAuth app). The email column from 0005 is reused.
ALTER TABLE installs ADD COLUMN password_hash TEXT;
ALTER TABLE installs ADD COLUMN login_failures INTEGER NOT NULL DEFAULT 0;
ALTER TABLE installs ADD COLUMN login_locked_until INTEGER;

CREATE INDEX IF NOT EXISTS installs_email_idx ON installs(email);
