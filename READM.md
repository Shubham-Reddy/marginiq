# MarginIQ: Channel Margin Recovery Engine

SQL-driven profitability analysis for cafes and restaurants that sell through both dine-in and delivery apps (Uber Eats, DoorDash, Menulog). It tells an owner which menu items lose money on which channel, and what to do about each one, with a dollar figure attached.

> **Data note:** the sales in this repo are synthetic (1,272 sales over 6 weeks, generated to mimic a Melbourne cafe). The method is real; the findings below describe the synthetic cafe, not a real business. [Update this line once you run it on a real cafe's export.]

## The problem

Delivery apps take 25-30% commission per order. Most small operators have never worked out profit per item per channel, so an item that is profitable over the counter can quietly lose money on an app. Revenue goes up, the owner feels fine, and margin falls.

## What it does

1. Models sales, menu items, channel commission and packaging in PostgreSQL
2. Calculates profit per sale, per item, per channel
3. Shows how margin erodes as delivery share grows
4. Applies an overhead assumption (labour, rent) and recommends **KEEP / REPRICE / PULL** for each item and channel, with a monthly dollar impact

## Findings (synthetic cafe)

- Delivery cut margin roughly in half: Chicken Schnitzel Burger earns 64% dine-in vs 29% on Uber Eats
- Delivery apps took about $3,170 in commission and packaging on $9,282 of delivery sales over 6 weeks (34%)
- As delivery rose from 33% to about 51% of revenue, blended margin fell from 60% to about 53-55%
- With 30% overhead, 1 item/channel combination loses money, 8 need repricing, 9 are fine
- Acting on the recommendations is worth roughly $307 a month for this one cafe
- Two supplier price rises (avocado, chicken) cut those items' weekly margin by up to about 11 points, visible only because costs are stored as history

## Schema

`sales_channels`, `menu_items`, `packaging_costs`, `sales`, `ingredient_cost_history` (add your ER diagram here)

## SQL techniques demonstrated

| Area | Where |
|---|---|
| Multi-table joins, conditional logic (`CASE`), chained CTEs | profit per sale, recommendation query |
| Window functions: `LAG`, running totals, moving average, `RANK`, z-score anomaly detection | `marginiq_stage5_trends.sql` |
| `LATERAL` join for point-in-time cost lookup | `v_sale_profit_hist` |
| Constraints, data-quality report, staging and cleaning of messy imports | `marginiq_stage6_integrity.sql` |
| Indexing proven with `EXPLAIN ANALYZE` (27.6 ms to 3.4 ms on 500k rows) | `marginiq_stage7_production.sql` |
| Views, SQL function with parameters, materialized view, stored procedure | `marginiq_stage7_production.sql` |

## How to run

1. Create the four base tables and load reference data (see schema section)
2. Run `marginiq_sales_seed.sql` to load the synthetic sales
3. Run the stage 5, 6 and 7 files in order
4. Try `SELECT * FROM get_recommendations(20, 15);` to see how the advice changes with different overhead and target margin

## Limitations and next steps

- Overhead is a flat percentage, not modelled from real labour and rent
- Assumes unit volume does not change when prices change (no price elasticity)
- Delivery sells at the dine-in price; real apps often use marked-up menus
- Next: validate with a real cafe's POS export and delivery payout statement
