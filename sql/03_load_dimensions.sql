-- Rebuild the four small dimensions from the OLTP tables.
DROP TABLE IF EXISTS olap.fact_sale;
DROP TABLE IF EXISTS olap.fact_order;

CREATE OR REPLACE TABLE olap.dim_date AS
WITH dates AS (
    SELECT date_value::DATE AS full_date
    FROM generate_series(
        (SELECT LEAST(MIN(order_date), (SELECT MIN(invoice_date) FROM oltp.invoices)) FROM oltp.orders),
        (SELECT GREATEST(MAX(order_date), (SELECT MAX(invoice_date) FROM oltp.invoices)) FROM oltp.orders),
        INTERVAL 1 DAY
    ) AS calendar(date_value)
)
SELECT
    strftime(full_date, '%Y%m%d')::INTEGER AS date_key,
    full_date,
    strftime(full_date, '%B') AS month_name,
    EXTRACT(YEAR FROM full_date)::SMALLINT AS calendar_year,
    ((EXTRACT(MONTH FROM full_date)::INTEGER + 1) % 12 + 1)::SMALLINT AS fiscal_month,
    (FLOOR(((EXTRACT(MONTH FROM full_date)::INTEGER + 1) % 12) / 3.0) + 1)::SMALLINT AS fiscal_quarter,
    (EXTRACT(YEAR FROM full_date)
        + CASE WHEN EXTRACT(MONTH FROM full_date) >= 11 THEN 1 ELSE 0 END
    )::SMALLINT AS fiscal_year
FROM dates;

CREATE OR REPLACE TABLE olap.dim_customer AS
SELECT
    ROW_NUMBER() OVER (ORDER BY customer.customer_id) AS customer_key,
    customer.customer_id,
    customer.customer_name,
    category.customer_category_name AS customer_category,
    buying_group.buying_group_name AS buying_group,
    city.city_name AS city,
    state.state_province_name AS state_province,
    country.country_name AS country,
    state.sales_territory,
    DATE '1900-01-01' AS effective_start_date,
    DATE '9999-12-31' AS effective_end_date,
    TRUE AS is_current
FROM oltp.customers customer
JOIN oltp.customer_categories category USING (customer_category_id)
LEFT JOIN oltp.buying_groups buying_group USING (buying_group_id)
JOIN oltp.cities city ON city.city_id = customer.delivery_city_id
JOIN oltp.state_provinces state USING (state_province_id)
JOIN oltp.countries country USING (country_id);

CREATE OR REPLACE TABLE olap.dim_employee AS
SELECT
    ROW_NUMBER() OVER (ORDER BY person_id) AS employee_key,
    person_id,
    full_name AS employee_name
FROM oltp.people
WHERE is_salesperson;

CREATE OR REPLACE TABLE olap.dim_product AS
SELECT
    ROW_NUMBER() OVER (ORDER BY item.stock_item_id) AS product_key,
    item.stock_item_id,
    item.stock_item_name AS product_name,
    category.stock_group_name AS product_category,
    item.brand
FROM oltp.stock_items item
LEFT JOIN (
    SELECT stock_item_id, MIN(stock_group_id) AS stock_group_id
    FROM oltp.stock_item_stock_groups
    GROUP BY stock_item_id
) first_category USING (stock_item_id)
LEFT JOIN oltp.stock_groups category USING (stock_group_id);
