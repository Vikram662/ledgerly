-- Cloud copy of each user's app data (workers, attendance, bills, khata...).
-- The phone keeps its own SQLite database and syncs it here, so data comes
-- back after a reinstall or on a new phone.

-- Stable account id. `install_id` moves to the new phone on login; the
-- account id does not, so the synced data stays with the account.
ALTER TABLE installs ADD COLUMN account_id TEXT;
UPDATE installs SET account_id = install_id WHERE account_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS installs_account_idx ON installs(account_id);

-- One row per app row. `data` is the row as JSON (NULL once deleted).
-- `changed_at` is the phone's time of the change in ms: the newest change
-- wins. `seq` orders changes per account so a phone pulls only what is new.
-- The primary key is the app's UUID, so the same row is never stored twice.
CREATE TABLE IF NOT EXISTS sync_rows (
  account_id TEXT NOT NULL,
  tbl TEXT NOT NULL,
  row_id TEXT NOT NULL,
  data TEXT,
  deleted INTEGER NOT NULL DEFAULT 0,
  changed_at INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  PRIMARY KEY (account_id, tbl, row_id)
);

CREATE INDEX IF NOT EXISTS sync_rows_seq_idx ON sync_rows(account_id, seq);
