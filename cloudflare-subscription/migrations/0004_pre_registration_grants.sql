CREATE TABLE IF NOT EXISTS complimentary_grants (
  phone_key TEXT PRIMARY KEY,
  complimentary_until INTEGER NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
