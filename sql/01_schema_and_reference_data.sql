-- MarginIQ: schema and reference data (PostgreSQL)
-- Run this first, then 02_seed_sales.sql, then 03 to 05 in order.

CREATE TABLE sales_channels (
    channel_id      SERIAL PRIMARY KEY,
    channel_name    VARCHAR(50),
    commission_rate DECIMAL(5,2)
);

CREATE TABLE menu_items (
    item_id         SERIAL PRIMARY KEY,
    item_name       VARCHAR(50),
    dine_in_price   DECIMAL(5,2),
    ingredient_cost DECIMAL(5,2)
);

CREATE TABLE sales (
    sale_id        SERIAL PRIMARY KEY,
    item_id        INTEGER NOT NULL,
    channel_id     INTEGER NOT NULL,
    quantity       INTEGER NOT NULL,
    sale_timestamp TIMESTAMP NOT NULL,
    FOREIGN KEY (item_id)    REFERENCES menu_items(item_id),
    FOREIGN KEY (channel_id) REFERENCES sales_channels(channel_id)
);

CREATE TABLE packaging_costs (
    packaging_id   SERIAL PRIMARY KEY,
    item_id        INTEGER NOT NULL UNIQUE,
    packaging_cost DECIMAL(5,2) NOT NULL,
    FOREIGN KEY (item_id) REFERENCES menu_items(item_id)
);

INSERT INTO sales_channels (channel_name, commission_rate) VALUES
('Dine-in', 0), ('Uber Eats', 30), ('DoorDash', 28), ('Menulog', 25);

INSERT INTO menu_items (item_name, dine_in_price, ingredient_cost) VALUES
('Flat White', 4.80, 0.90),
('Avocado Toast', 16.50, 4.20),
('Chicken Schnitzel Burger', 18.90, 6.80),
('Caesar Salad', 15.00, 4.50),
('Bacon & Egg Roll', 9.50, 2.60),
('Banana Bread', 7.00, 1.40);

INSERT INTO packaging_costs (item_id, packaging_cost) VALUES
(1, 0.45), (2, 0.80), (3, 0.95), (4, 1.10), (5, 0.60), (6, 0.40);
