ALTER TABLE payments ADD COLUMN order_id TEXT NOT NULL DEFAULT '';
ALTER TABLE payments ADD COLUMN reference TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_order_id ON payments(order_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_payment_type ON ledger(payment_id, type);
