-- MarginIQ Stage 5: trends and advanced SQL (window functions)
-- Run the VIEW first (select it, Ctrl+Enter). Then run each query below on its own.

-- ============================================================
-- 5.0 Reusable view: one row per sale with every cost split out
-- ============================================================
CREATE OR REPLACE VIEW v_sale_profit AS
SELECT
    s.sale_id,
    s.sale_timestamp,
    s.sale_timestamp::date AS sale_date,
    m.item_id,
    m.item_name,
    c.channel_id,
    c.channel_name,
    (c.channel_name <> 'Dine-in') AS is_delivery,
    s.quantity,
    m.dine_in_price * s.quantity AS revenue,
    m.dine_in_price * s.quantity * c.commission_rate / 100 AS commission,
    m.ingredient_cost * s.quantity AS ingredient_cost,
    CASE WHEN c.channel_name <> 'Dine-in'
         THEN p.packaging_cost * s.quantity ELSE 0 END AS packaging,
    m.dine_in_price * s.quantity
      - m.dine_in_price * s.quantity * c.commission_rate / 100
      - m.ingredient_cost * s.quantity
      - CASE WHEN c.channel_name <> 'Dine-in'
             THEN p.packaging_cost * s.quantity ELSE 0 END AS net_profit
FROM sales s
JOIN menu_items m ON s.item_id = m.item_id
JOIN sales_channels c ON s.channel_id = c.channel_id
JOIN packaging_costs p ON s.item_id = p.item_id;


-- ============================================================
-- 5.1 Weekly margin by channel group, with week-over-week change (LAG)
-- ============================================================
WITH weekly AS (
    SELECT
        date_trunc('week', sale_date)::date AS week_start,
        CASE WHEN is_delivery THEN 'Delivery' ELSE 'Dine-in' END AS channel_group,
        SUM(revenue) AS revenue,
        SUM(net_profit) AS net_profit
    FROM v_sale_profit
    GROUP BY 1, 2
)
SELECT
    week_start,
    channel_group,
    ROUND(revenue, 2) AS revenue,
    ROUND(net_profit / revenue * 100, 1) AS margin_pct,
    ROUND(net_profit / revenue * 100
          - LAG(net_profit / revenue * 100) OVER (PARTITION BY channel_group ORDER BY week_start), 1)
        AS margin_change_vs_prev_week
FROM weekly
ORDER BY channel_group, week_start;


-- ============================================================
-- 5.2 The core story: delivery share grows, blended margin falls
-- ============================================================
SELECT
    date_trunc('week', sale_date)::date AS week_start,
    ROUND(SUM(revenue) FILTER (WHERE is_delivery) / SUM(revenue) * 100, 1) AS delivery_share_pct,
    ROUND(SUM(net_profit) / SUM(revenue) * 100, 1) AS blended_margin_pct,
    ROUND(SUM(net_profit), 2) AS total_profit
FROM v_sale_profit
GROUP BY 1
ORDER BY 1;


-- ============================================================
-- 5.3 Daily profit: running total and 7-day moving average
-- ============================================================
WITH daily AS (
    SELECT sale_date, SUM(net_profit) AS daily_profit
    FROM v_sale_profit
    GROUP BY sale_date
)
SELECT
    sale_date,
    ROUND(daily_profit, 2) AS daily_profit,
    ROUND(SUM(daily_profit) OVER (ORDER BY sale_date), 2) AS running_total,
    ROUND(AVG(daily_profit) OVER (ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2)
        AS moving_avg_7d
FROM daily
ORDER BY sale_date;


-- ============================================================
-- 5.4 Anomaly detection: days whose margin is unusual (z-score)
-- ============================================================
WITH daily AS (
    SELECT sale_date,
           SUM(net_profit) / SUM(revenue) * 100 AS margin_pct,
           SUM(revenue) FILTER (WHERE is_delivery) / SUM(revenue) * 100 AS delivery_share_pct
    FROM v_sale_profit
    GROUP BY sale_date
),
scored AS (
    SELECT *,
           (margin_pct - AVG(margin_pct) OVER ()) / NULLIF(STDDEV_SAMP(margin_pct) OVER (), 0) AS z_score
    FROM daily
)
SELECT sale_date,
       ROUND(margin_pct, 1) AS margin_pct,
       ROUND(delivery_share_pct, 1) AS delivery_share_pct,
       ROUND(z_score, 2) AS z_score
FROM scored
WHERE ABS(z_score) > 1.5
ORDER BY ABS(z_score) DESC;


-- ============================================================
-- 5.5 Day-part analysis: when does delivery hurt most?
-- ============================================================
SELECT
    CASE WHEN EXTRACT(HOUR FROM sale_timestamp) < 11 THEN '1 Breakfast (7-10)'
         WHEN EXTRACT(HOUR FROM sale_timestamp) < 14 THEN '2 Lunch (11-13)'
         ELSE '3 Afternoon (14-15)' END AS day_part,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(SUM(revenue) FILTER (WHERE is_delivery) / SUM(revenue) * 100, 1) AS delivery_share_pct,
    ROUND(SUM(net_profit) / SUM(revenue) * 100, 1) AS margin_pct
FROM v_sale_profit
GROUP BY 1
ORDER BY 1;


-- ============================================================
-- 5.6 Rank items by profit within each channel (RANK + PARTITION BY)
-- ============================================================
SELECT
    channel_name,
    item_name,
    ROUND(SUM(net_profit), 2) AS total_profit,
    RANK() OVER (PARTITION BY channel_name ORDER BY SUM(net_profit) DESC) AS profit_rank
FROM v_sale_profit
GROUP BY channel_name, item_name
ORDER BY channel_name, profit_rank;
