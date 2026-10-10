CREATE TABLE IF NOT EXISTS wallets (
  id TEXT PRIMARY KEY,
  balance_tzs INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL,
  wallet_id TEXT NOT NULL,
  amount_tzs INTEGER NOT NULL,
  phone TEXT NOT NULL,
  provider TEXT NOT NULL,
  status TEXT NOT NULL,
  mongike_id TEXT,
  reference TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(mongike_id),
  UNIQUE(order_id)
);

CREATE TABLE IF NOT EXISTS ledger (
  id TEXT PRIMARY KEY,
  wallet_id TEXT NOT NULL,
  payment_id TEXT,
  type TEXT NOT NULL,
  amount_tzs INTEGER NOT NULL,
  balance_after INTEGER NOT NULL,
  reference TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS webhook_events (
  id TEXT PRIMARY KEY,
  received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  payload TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_payments_wallet ON payments(wallet_id);
CREATE INDEX IF NOT EXISTS idx_ledger_wallet ON ledger(wallet_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_payment_type ON ledger(payment_id, type);
