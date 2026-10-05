# MarginIQ: Channel Margin Recovery Engine

Cafes and restaurants that sell through delivery apps rarely know what each menu item actually earns on each channel. MarginIQ works it out and tells the owner what to do: **KEEP, REPRICE or PULL**, with a monthly dollar figure attached.

Two parts:

1. **A PostgreSQL model** (schema, views, window functions, a recommendation function) that is the analytical engine.
2. **A working web tool** (`docs/index.html`) where a cafe loads its own sales CSV, enters menu costs and commission rates, and gets the same verdicts in the browser. Nothing is uploaded; everything runs locally in the page.

> **Data note:** the sample sales are synthetic (1,272 sales over 6 weeks, generated to mimic a Melbourne cafe). The method is real and the code runs on any cafe's export. The findings below describe the synthetic cafe, not a real business.

**Live demo:** https://shubham-reddy.github.io/marginiq/

## The problem

Delivery apps take 25 to 30% commission per order. Most small operators have never worked out profit per item per channel, so an item that is profitable over the counter can quietly lose money on an app. Revenue goes up, the owner feels fine, and margin falls.

## Findings (synthetic cafe)

- Delivery cut margin roughly in half: the Chicken Schnitzel Burger earns 64% dine-in but 29% on Uber Eats.
- Delivery apps took about $3,170 in commission and packaging on $9,282 of delivery sales over 6 weeks (34%).
- As delivery rose from 33% to about 51% of revenue, blended margin fell from 60% to about 53%.
- With 30% overhead assumed, 1 item-and-channel combination loses money, 8 need repricing and 9 are fine.
- Acting on the recommendations is worth about $307 a month for this one cafe.
- Two supplier price rises (avocado, chicken) cut those items' weekly margin by up to about 11 points. This is visible only because ingredient costs are stored as history.

## How the decision is made

- Profit per sale = price x quantity, less commission, ingredient cost and (delivery only) packaging.
- Overhead (labour, rent) is an assumption, 30% of revenue by default, and the target margin is 10%.
- **KEEP** if margin after overhead meets the target.
- **REPRICE** if a delivery price up to 25% above the dine-in price restores the target.
- **PULL** if it cannot be fixed that way and the line loses money after overhead.
- Monthly impact scales the data period to 30 days.

## Repository layout

| Path | What it is |
|---|---|
| `sql/01_schema_and_reference_data.sql` | Four core tables, channels, menu and packaging costs |
| `sql/02_seed_sales.sql` | 1,272 synthetic sales |
| `sql/03_trends_window_functions.sql` | `v_sale_profit` view, weekly margin with `LAG`, running totals, moving average, z-score anomalies, day-parts, `RANK` |
| `sql/04_integrity_and_import.sql` | Constraints, ingredient cost history with `LATERAL` join, data-quality report, staging pattern for messy imports |
| `sql/05_production_engine.sql` | Indexes proven with `EXPLAIN ANALYZE`, `get_recommendations()` function, materialized view, refresh procedure |
| `docs/index.html` | The working tool (single file, no build step), served by GitHub Pages |
| `data/sample_sales.csv` | The same sample sales as a CSV you can upload to the tool |

## SQL techniques demonstrated

| Area | Where |
|---|---|
| Multi-table joins, conditional logic (`CASE`), chained CTEs | recommendation function |
| Window functions: `LAG`, running total, moving average, `RANK`, z-score anomaly detection | `03_trends_window_functions.sql` |
| `LATERAL` join for point-in-time cost lookup | `v_sale_profit_hist` in `04` |
| Constraints, data-quality report, staging and cleaning of messy imports | `04_integrity_and_import.sql` |
| Indexing proven with `EXPLAIN ANALYZE` (27.6 ms to 3.4 ms on 500k rows, local test) | `05_production_engine.sql` |
| Views, parameterised SQL function, materialized view, stored procedure | `05_production_engine.sql` |

## Run the SQL

1. Create a PostgreSQL database (a free Neon project works).
2. Run `sql/01` to `sql/05` in order.
3. Try `SELECT * FROM get_recommendations();` and `SELECT * FROM get_recommendations(20, 15);` to see how the advice changes with a different overhead and target margin.

## Run the tool

Open the live demo above, or open `docs/index.html` in any browser. Click **Use the sample cafe**, or upload a CSV with these columns (any order, matched by name):

```
item,channel,quantity,sold_at
Flat White,Dine-in,2,2026-09-14 08:15:00
Caesar Salad,Uber Eats,1,14/09/2026 12:40
```

Then edit the menu prices, ingredient costs, packaging and channel commission rates. Rows that cannot be used are listed with the reason. The tool's calculation was checked against `get_recommendations()` and gives identical results on the sample data.

## Limitations and next steps

- Overhead is a flat percentage, not modelled from real labour and rent.
- Assumes unit volume does not change when prices change (no price elasticity).
- Delivery is assumed to sell at the dine-in price; real apps often use marked-up menus.
- The tool does not save data between visits and has no accounts.
- Next: validate on a real cafe's POS export and delivery payout statement, then add accounts and saved history.
