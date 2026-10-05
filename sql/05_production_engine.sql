-- MarginIQ Stage 7: production-grade engineering
-- Needs Stage 5 (view v_sale_profit) and Stage 6 to have been run first.
-- Run section by section. Sections 7.2 and 7.5 create and drop a temporary 500k-row table.

-- ============================================================
-- 7.1 Indexes on the columns your queries filter and join on
-- (Postgres does NOT index foreign keys automatically)
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_sales_item_time ON sales (item_id, sale_timestamp);
CREATE INDEX IF NOT EXISTS idx_sales_channel   ON sales (channel_id);
CREATE INDEX IF NOT EXISTS idx_sales_time      ON sales (sale_timestamp);


-- ============================================================
-- 7.2 Prove an index helps: build a 500k-row test table, EXPLAIN before and after
-- ============================================================
DROP TABLE IF EXISTS sales_big;
CREATE TABLE sales_big AS
SELECT
    g AS sale_id,
    1 + (random() * 5)::int AS item_id,
    1 + (random() * 3)::int AS channel_id,
    1 + (random() * 2)::int AS quantity,
    TIMESTAMP '2026-01-01' + random() * INTERVAL '280 days' AS sale_timestamp
FROM generate_series(1, 500000) g;
ANALYZE sales_big;

-- BEFORE: no index. Look for "Seq Scan" and the Execution Time at the bottom.
EXPLAIN ANALYZE
SELECT COUNT(*), SUM(quantity)
FROM sales_big
WHERE item_id = 3
  AND sale_timestamp >= '2026-09-14' AND sale_timestamp < '2026-09-21';

CREATE INDEX idx_sales_big_item_time ON sales_big (item_id, sale_timestamp);
ANALYZE sales_big;

-- AFTER: same query. Look for "Index Scan" / "Bitmap Index Scan" and the new, lower time.
EXPLAIN ANALYZE
SELECT COUNT(*), SUM(quantity)
FROM sales_big
WHERE item_id = 3
  AND sale_timestamp >= '2026-09-14' AND sale_timestamp < '2026-09-21';


-- ============================================================
-- 7.3 The recommendation engine as a reusable function
-- Usage: SELECT * FROM get_recommendations();            -- defaults 30% / 10%
--        SELECT * FROM get_recommendations(20, 15);      -- what if overhead is 20%?
-- ============================================================
CREATE OR REPLACE FUNCTION get_recommendations(
    p_overhead_pct NUMERIC DEFAULT 30,
    p_target_margin_pct NUMERIC DEFAULT 10
)
RETURNS TABLE (
    item_name VARCHAR,
    channel_name VARCHAR,
    units BIGINT,
    margin_after_overhead NUMERIC,
    action TEXT,
    current_price NUMERIC,
    suggested_price NUMERIC,
    monthly_impact NUMERIC
)
LANGUAGE sql STABLE AS $$
    WITH params AS (
        SELECT p_overhead_pct AS overhead_pct,
               p_target_margin_pct AS target_margin_pct,
               (MAX(sale_timestamp)::date - MIN(sale_timestamp)::date + 1) AS data_days
        FROM sales
    ),
    combo AS (
        SELECT item_id, channel_id,
               SUM(quantity) AS units,
               SUM(revenue) AS revenue,
               SUM(net_profit) AS net_profit
        FROM v_sale_profit
        WHERE is_delivery
        GROUP BY item_id, channel_id
    ),
    scored AS (
        SELECT m.item_name, c.channel_name, k.units, m.dine_in_price,
               k.net_profit - k.revenue * pr.overhead_pct / 100 AS profit_after_overhead,
               (k.net_profit / k.revenue * 100) - pr.overhead_pct AS margin_after,
               (m.ingredient_cost + p.packaging_cost)
                 / (1 - c.commission_rate / 100 - pr.overhead_pct / 100 - pr.target_margin_pct / 100)
                 AS sug_price,
               pr.target_margin_pct, pr.data_days
        FROM combo k
        JOIN menu_items m ON k.item_id = m.item_id
        JOIN sales_channels c ON k.channel_id = c.channel_id
        JOIN packaging_costs p ON k.item_id = p.item_id
        CROSS JOIN params pr
    ),
    actioned AS (
        SELECT *,
               CASE WHEN margin_after >= target_margin_pct THEN 'KEEP'
                    WHEN sug_price <= dine_in_price * 1.25 THEN 'REPRICE'
                    WHEN margin_after < 0 THEN 'PULL'
                    ELSE 'REPRICE' END AS act
        FROM scored
    )
    SELECT item_name, channel_name, units,
           ROUND(margin_after, 1),
           act,
           ROUND(dine_in_price, 2),
           ROUND(sug_price, 2),
           ROUND(CASE act
                   WHEN 'KEEP' THEN 0
                   WHEN 'REPRICE' THEN units * LEAST(sug_price, dine_in_price * 1.25)
                                       * target_margin_pct / 100 - profit_after_overhead
                   ELSE -profit_after_overhead
                 END * 30.0 / data_days, 2)
    FROM actioned
    ORDER BY margin_after ASC;
$$;

SELECT * FROM get_recommendations();
SELECT * FROM get_recommendations(20, 15);


-- ============================================================
-- 7.4 Materialized view: precompute the heavy aggregate, refresh on demand
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_item_channel_profit AS
SELECT
    item_id, item_name, channel_id, channel_name,
    SUM(quantity) AS units,
    SUM(revenue) AS revenue,
    SUM(net_profit) AS net_profit,
    ROUND(SUM(net_profit) / SUM(revenue) * 100, 1) AS margin_pct
FROM v_sale_profit
GROUP BY item_id, item_name, channel_id, channel_name;

-- A unique index is required to refresh without blocking readers
CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_item_channel ON mv_item_channel_profit (item_id, channel_id);

-- A stored procedure to refresh it after new sales are loaded
CREATE OR REPLACE PROCEDURE refresh_marginiq()
LANGUAGE sql AS $$
    REFRESH MATERIALIZED VIEW mv_item_channel_profit;
$$;

CALL refresh_marginiq();
SELECT * FROM mv_item_channel_profit ORDER BY margin_pct;
-- In production, with live readers, run this instead (outside a procedure):
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_item_channel_profit;


-- ============================================================
-- 7.5 Clean up the temporary test table (keeps your free-tier storage small)
-- ============================================================
DROP TABLE IF EXISTS sales_big;
