-- MarginIQ Stage 6: data integrity, cost history, and a messy-import pipeline
-- Run section by section (select a block, Ctrl+Enter), or the whole file with Alt+X.

-- ============================================================
-- 6.1 Constraints: make bad data impossible, not just unlikely
-- ============================================================
ALTER TABLE sales_channels
    ADD CONSTRAINT uq_channel_name UNIQUE (channel_name),
    ADD CONSTRAINT chk_commission_range CHECK (commission_rate BETWEEN 0 AND 100);

ALTER TABLE menu_items
    ADD CONSTRAINT uq_item_name UNIQUE (item_name),
    ADD CONSTRAINT chk_item_money CHECK (dine_in_price > 0 AND ingredient_cost >= 0);

ALTER TABLE sales
    ADD CONSTRAINT chk_quantity_positive CHECK (quantity > 0);

ALTER TABLE packaging_costs
    ADD CONSTRAINT chk_packaging_nonneg CHECK (packaging_cost >= 0);


-- ============================================================
-- 6.2 Ingredient cost history: costs change, so store them over time
-- ============================================================
CREATE TABLE ingredient_cost_history (
    history_id      SERIAL PRIMARY KEY,
    item_id         INTEGER NOT NULL REFERENCES menu_items(item_id),
    ingredient_cost DECIMAL(5,2) NOT NULL CHECK (ingredient_cost >= 0),
    valid_from      DATE NOT NULL,
    UNIQUE (item_id, valid_from)
);

-- Starting costs, plus two supplier price increases partway through the period
INSERT INTO ingredient_cost_history (item_id, ingredient_cost, valid_from) VALUES
(1, 0.90, '2026-08-01'),
(2, 4.20, '2026-08-01'),
(3, 6.80, '2026-08-01'),
(4, 4.50, '2026-08-01'),
(5, 2.60, '2026-08-01'),
(6, 1.40, '2026-08-01'),
(2, 4.60, '2026-09-14'),   -- avocado price rise
(3, 7.40, '2026-09-21');   -- chicken price rise

-- Profit per sale using the cost that was in force on the sale date
CREATE OR REPLACE VIEW v_sale_profit_hist AS
SELECT
    s.sale_id,
    s.sale_timestamp::date AS sale_date,
    m.item_id,
    m.item_name,
    c.channel_name,
    (c.channel_name <> 'Dine-in') AS is_delivery,
    s.quantity,
    m.dine_in_price * s.quantity AS revenue,
    h.ingredient_cost * s.quantity AS ingredient_cost,
    m.dine_in_price * s.quantity
      - m.dine_in_price * s.quantity * c.commission_rate / 100
      - h.ingredient_cost * s.quantity
      - CASE WHEN c.channel_name <> 'Dine-in'
             THEN p.packaging_cost * s.quantity ELSE 0 END AS net_profit
FROM sales s
JOIN menu_items m ON s.item_id = m.item_id
JOIN sales_channels c ON s.channel_id = c.channel_id
JOIN packaging_costs p ON s.item_id = p.item_id
JOIN LATERAL (
    SELECT ingredient_cost
    FROM ingredient_cost_history ich
    WHERE ich.item_id = s.item_id
      AND ich.valid_from <= s.sale_timestamp::date
    ORDER BY ich.valid_from DESC
    LIMIT 1
) h ON TRUE;

-- Question this answers: how much margin did the supplier price rises cost us?
SELECT
    item_name,
    date_trunc('week', sale_date)::date AS week_start,
    ROUND(SUM(net_profit) / SUM(revenue) * 100, 1) AS margin_pct
FROM v_sale_profit_hist
WHERE item_name IN ('Avocado Toast', 'Chicken Schnitzel Burger')
GROUP BY item_name, 2
ORDER BY item_name, week_start;


-- ============================================================
-- 6.3 Data-quality report: one row per check, anything above 0 needs attention
-- ============================================================
SELECT 'sales with no packaging row' AS check_name, COUNT(*) AS issues
FROM sales s LEFT JOIN packaging_costs p ON s.item_id = p.item_id
WHERE p.item_id IS NULL
UNION ALL
SELECT 'items with no cost history', COUNT(*)
FROM menu_items m LEFT JOIN ingredient_cost_history h ON m.item_id = h.item_id
WHERE h.item_id IS NULL
UNION ALL
SELECT 'sales dated in the future', COUNT(*)
FROM sales WHERE sale_timestamp > NOW()
UNION ALL
SELECT 'possible duplicate sales (same item, channel, second)', COUNT(*)
FROM (
    SELECT item_id, channel_id, sale_timestamp
    FROM sales
    GROUP BY item_id, channel_id, sale_timestamp
    HAVING COUNT(*) > 1
) d
UNION ALL
SELECT 'items priced below ingredient cost', COUNT(*)
FROM menu_items WHERE dine_in_price <= ingredient_cost
UNION ALL
SELECT 'unusually large quantities (>10)', COUNT(*)
FROM sales WHERE quantity > 10;


-- ============================================================
-- 6.4 Importing a messy real-world export (staging pattern)
-- Real POS files arrive as text with stray spaces, odd casing, bad rows.
-- Load raw, then clean in SQL, then insert only what passes.
-- ============================================================
CREATE TABLE IF NOT EXISTS raw_sales_import (
    item_name    TEXT,
    channel_name TEXT,
    quantity     TEXT,
    sold_at      TEXT
);

-- Demo rows (a real file would be loaded via DBeaver: right-click the table, Import Data)
INSERT INTO raw_sales_import VALUES
('  flat white ',   'uber eats', '2',   '2026-10-05 08:15:00'),
('Caesar Salad',    'DoorDash',  '1',   '2026-10-05 12:40:00'),
('Banana Bread',    'Dine-in',   'two', '2026-10-05 09:05:00'),   -- bad quantity
('Mystery Special', 'Dine-in',   '1',   '2026-10-05 10:00:00');   -- unknown item

-- Rows that are clean and ready to insert
SELECT m.item_id, c.channel_id, r.quantity::int AS quantity, r.sold_at::timestamp AS sale_timestamp
FROM raw_sales_import r
JOIN menu_items m ON LOWER(TRIM(r.item_name)) = LOWER(m.item_name)
JOIN sales_channels c ON LOWER(TRIM(r.channel_name)) = LOWER(c.channel_name)
WHERE TRIM(r.quantity) ~ '^[0-9]+$';

-- Rows rejected, with the reason (this is what you send back to the café)
SELECT r.*,
       CASE WHEN m.item_id IS NULL THEN 'unknown item'
            WHEN c.channel_id IS NULL THEN 'unknown channel'
            ELSE 'bad quantity' END AS reject_reason
FROM raw_sales_import r
LEFT JOIN menu_items m ON LOWER(TRIM(r.item_name)) = LOWER(m.item_name)
LEFT JOIN sales_channels c ON LOWER(TRIM(r.channel_name)) = LOWER(c.channel_name)
WHERE m.item_id IS NULL OR c.channel_id IS NULL OR TRIM(r.quantity) !~ '^[0-9]+$';

-- When you are happy with a real import, uncomment to load the clean rows:
-- INSERT INTO sales (item_id, channel_id, quantity, sale_timestamp)
-- SELECT m.item_id, c.channel_id, r.quantity::int, r.sold_at::timestamp
-- FROM raw_sales_import r
-- JOIN menu_items m ON LOWER(TRIM(r.item_name)) = LOWER(m.item_name)
-- JOIN sales_channels c ON LOWER(TRIM(r.channel_name)) = LOWER(c.channel_name)
-- WHERE TRIM(r.quantity) ~ '^[0-9]+$';
-- TRUNCATE raw_sales_import;
