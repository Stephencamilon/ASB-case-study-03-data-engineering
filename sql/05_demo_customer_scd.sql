-- Demo only: customer 1 changes category on 2015-01-01.
-- This creates a synthetic second snapshot without changing the source CSV.
CREATE OR REPLACE TEMP TABLE changed_customer AS
SELECT
    customer.customer_id,
    customer.customer_name,
    category.customer_category_name AS customer_category,
    buying_group.buying_group_name AS buying_group,
    city.city_name AS city,
    state.state_province_name AS state_province,
    country.country_name AS country,
    state.sales_territory
FROM oltp.customers customer
JOIN oltp.customer_categories category
  ON category.customer_category_id =
     CASE WHEN customer.customer_id = 1 THEN 2 ELSE customer.customer_category_id END
LEFT JOIN oltp.buying_groups buying_group USING (buying_group_id)
JOIN oltp.cities city ON city.city_id = customer.delivery_city_id
JOIN oltp.state_provinces state USING (state_province_id)
JOIN oltp.countries country USING (country_id)
WHERE customer.customer_id = 1;

-- Close the old version the day before the category change.
UPDATE olap.dim_customer
SET effective_end_date = DATE '2014-12-31',
    is_current = FALSE
WHERE customer_id = 1
  AND is_current
  AND customer_category <> (SELECT customer_category FROM changed_customer);

-- Add the new version once. Rerunning this file will not create another copy.
INSERT INTO olap.dim_customer
SELECT
    (SELECT COALESCE(MAX(customer_key), 0) + 1 FROM olap.dim_customer),
    customer_id,
    customer_name,
    customer_category,
    buying_group,
    city,
    state_province,
    country,
    sales_territory,
    DATE '2015-01-01',
    DATE '9999-12-31',
    TRUE
FROM changed_customer
WHERE NOT EXISTS (
    SELECT 1
    FROM olap.dim_customer current_version
    WHERE current_version.customer_id = changed_customer.customer_id
      AND current_version.effective_start_date = DATE '2015-01-01'
);
