-- EMPIRE GESTION - Schema initial v0.1 (Cloudflare D1 / SQLite)
-- Ce script cree les tables metier sans supprimer la table interne _cf_KV.
-- A executer dans la console D1 de empire-gestion-db.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS business_units (
 id INTEGER PRIMARY KEY,
 code TEXT NOT NULL UNIQUE,
 name TEXT NOT NULL UNIQUE,
 display_order INTEGER NOT NULL UNIQUE,
 description TEXT,
 is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

INSERT OR IGNORE INTO business_units (code,name,display_order,description) VALUES
('WATER','EMPIRE WATER',1,'Production eau potable, emballages, stocks et distribution'),
('INDUSTRIES','EMPIRE INDUSTRIES',2,'Fabrication, production, matieres premieres et qualite'),
('MARKET','EMPIRE MARKET',3,'Commerce, distribution, achats, ventes et import-export'),
('PETROENERGY','EMPIRE PETROENERGY',4,'Hydrocarbures, approvisionnements, stocks et ventes'),
('MINING','EMPIRE MINING',5,'Sites miniers, equipements, production, couts et securite'),
('TRANSPORT','EMPIRE TRANSPORT',6,'Vehicules, trajets, carburant, entretien et livraisons');

CREATE TABLE IF NOT EXISTS app_users (
 id INTEGER PRIMARY KEY,
 full_name TEXT NOT NULL,
 email TEXT NOT NULL UNIQUE,
 password_hash TEXT,
 role TEXT NOT NULL DEFAULT 'operator' CHECK (role IN ('super_admin','director','manager','accountant','stock_manager','sales','operator','viewer')),
 is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS user_unit_access (
 user_id INTEGER NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
 unit_id INTEGER NOT NULL REFERENCES business_units(id) ON DELETE CASCADE,
 can_view INTEGER NOT NULL DEFAULT 1 CHECK (can_view IN (0,1)),
 can_create INTEGER NOT NULL DEFAULT 0 CHECK (can_create IN (0,1)),
 can_edit INTEGER NOT NULL DEFAULT 0 CHECK (can_edit IN (0,1)),
 can_approve INTEGER NOT NULL DEFAULT 0 CHECK (can_approve IN (0,1)),
 PRIMARY KEY (user_id,unit_id)
);

CREATE TABLE IF NOT EXISTS currencies (
 code TEXT PRIMARY KEY CHECK (code IN ('XOF','USD','EUR','CNY')),
 name TEXT NOT NULL,
 symbol TEXT NOT NULL
);
INSERT OR IGNORE INTO currencies (code,name,symbol) VALUES
('XOF','Franc CFA BCEAO','FCFA'),('USD','Dollar americain','$'),
('EUR','Euro','EUR'),('CNY','Yuan chinois','CNY');

CREATE TABLE IF NOT EXISTS exchange_rates (
 id INTEGER PRIMARY KEY,
 from_currency TEXT NOT NULL REFERENCES currencies(code),
 to_currency TEXT NOT NULL REFERENCES currencies(code),
 rate REAL NOT NULL CHECK (rate > 0),
 effective_at TEXT NOT NULL,
 source TEXT,
 created_by INTEGER REFERENCES app_users(id),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 UNIQUE (from_currency,to_currency,effective_at)
);

CREATE TABLE IF NOT EXISTS parties (
 id INTEGER PRIMARY KEY,
 party_type TEXT NOT NULL CHECK (party_type IN ('customer','supplier','both','other')),
 name TEXT NOT NULL,
 phone TEXT,
 email TEXT,
 address TEXT,
 tax_number TEXT,
 notes TEXT,
 is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS products (
 id INTEGER PRIMARY KEY,
 unit_id INTEGER NOT NULL REFERENCES business_units(id),
 sku TEXT,
 name TEXT NOT NULL,
 category TEXT,
 unit_of_measure TEXT NOT NULL DEFAULT 'piece',
 purchase_price REAL NOT NULL DEFAULT 0 CHECK (purchase_price >= 0),
 sale_price REAL NOT NULL DEFAULT 0 CHECK (sale_price >= 0),
 currency_code TEXT NOT NULL DEFAULT 'XOF' REFERENCES currencies(code),
 minimum_stock REAL NOT NULL DEFAULT 0 CHECK (minimum_stock >= 0),
 is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 UNIQUE (unit_id,sku)
);

CREATE TABLE IF NOT EXISTS stock_movements (
 id INTEGER PRIMARY KEY,
 unit_id INTEGER NOT NULL REFERENCES business_units(id),
 product_id INTEGER NOT NULL REFERENCES products(id),
 movement_type TEXT NOT NULL CHECK (movement_type IN ('opening','purchase','sale','return_in','return_out','adjustment_in','adjustment_out','production_in','production_out','transfer_in','transfer_out')),
 quantity REAL NOT NULL CHECK (quantity > 0),
 unit_cost REAL NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
 currency_code TEXT NOT NULL DEFAULT 'XOF' REFERENCES currencies(code),
 reference TEXT,
 movement_date TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 notes TEXT,
 created_by INTEGER REFERENCES app_users(id),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS transactions (
 id INTEGER PRIMARY KEY,
 unit_id INTEGER NOT NULL REFERENCES business_units(id),
 transaction_type TEXT NOT NULL CHECK (transaction_type IN ('sale','purchase','expense','income','customer_credit','supplier_debt','refund','transfer')),
 status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','pending','validated','cancelled')),
 party_id INTEGER REFERENCES parties(id),
 reference TEXT,
 transaction_date TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 due_date TEXT,
 currency_code TEXT NOT NULL DEFAULT 'XOF' REFERENCES currencies(code),
 subtotal REAL NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
 discount_amount REAL NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
 tax_amount REAL NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
 shipping_cost REAL NOT NULL DEFAULT 0 CHECK (shipping_cost >= 0),
 other_cost REAL NOT NULL DEFAULT 0 CHECK (other_cost >= 0),
 total_amount REAL NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
 exchange_rate_to_xof REAL CHECK (exchange_rate_to_xof IS NULL OR exchange_rate_to_xof > 0),
 notes TEXT,
 created_by INTEGER REFERENCES app_users(id),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS transaction_items (
 id INTEGER PRIMARY KEY,
 transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
 product_id INTEGER REFERENCES products(id),
 description TEXT NOT NULL,
 quantity REAL NOT NULL DEFAULT 1 CHECK (quantity > 0),
 unit_price REAL NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
 discount_amount REAL NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
 line_total REAL NOT NULL DEFAULT 0 CHECK (line_total >= 0)
);

CREATE TABLE IF NOT EXISTS payments (
 id INTEGER PRIMARY KEY,
 transaction_id INTEGER NOT NULL REFERENCES transactions(id),
 payment_date TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 amount REAL NOT NULL CHECK (amount > 0),
 currency_code TEXT NOT NULL REFERENCES currencies(code),
 payment_method TEXT NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash','bank_transfer','mobile_money','card','cheque','other')),
 reference TEXT,
 notes TEXT,
 received_or_paid_by INTEGER REFERENCES app_users(id),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS import_costs (
 id INTEGER PRIMARY KEY,
 transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
 cost_type TEXT NOT NULL CHECK (cost_type IN ('goods','international_transport','insurance','customs_duty','transit_handling','local_transport','other')),
 description TEXT,
 amount REAL NOT NULL CHECK (amount >= 0),
 currency_code TEXT NOT NULL REFERENCES currencies(code),
 exchange_rate_to_xof REAL NOT NULL CHECK (exchange_rate_to_xof > 0),
 amount_xof REAL NOT NULL CHECK (amount_xof >= 0),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS expense_categories (
 id INTEGER PRIMARY KEY,
 unit_id INTEGER REFERENCES business_units(id),
 name TEXT NOT NULL,
 is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
 UNIQUE (unit_id,name)
);

CREATE TABLE IF NOT EXISTS audit_log (
 id INTEGER PRIMARY KEY,
 user_id INTEGER REFERENCES app_users(id),
 unit_id INTEGER REFERENCES business_units(id),
 action TEXT NOT NULL,
 entity_type TEXT NOT NULL,
 entity_id INTEGER,
 details TEXT,
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_products_unit_name ON products(unit_id,name);
CREATE INDEX IF NOT EXISTS idx_stock_product_date ON stock_movements(product_id,movement_date);
CREATE INDEX IF NOT EXISTS idx_transactions_unit_date ON transactions(unit_id,transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_type_status ON transactions(transaction_type,status);
CREATE INDEX IF NOT EXISTS idx_transactions_party ON transactions(party_id);
CREATE INDEX IF NOT EXISTS idx_transactions_due_date ON transactions(due_date);
CREATE INDEX IF NOT EXISTS idx_payments_transaction_date ON payments(transaction_id,payment_date);
CREATE INDEX IF NOT EXISTS idx_import_costs_transaction ON import_costs(transaction_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at);

-- Verification apres execution :
-- SELECT code,name,display_order FROM business_units ORDER BY display_order;
-- SELECT code,name FROM currencies ORDER BY code;
-- SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
