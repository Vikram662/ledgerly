ALTER TABLE installs ADD COLUMN complimentary_until INTEGER;
ALTER TABLE installs ADD COLUMN complimentary_note TEXT;

CREATE INDEX IF NOT EXISTS installs_phone_idx ON installs(phone);
CREATE INDEX IF NOT EXISTS installs_complimentary_idx
  ON installs(complimentary_until);
