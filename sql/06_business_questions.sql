-- 1. Sales, quantity and profit by calendar month and fiscal year.
SELECT
    date.calendar_year,
    date.month_name,
    date.fiscal_year,
    date.fiscal_quarter,
    SUM(sale.sales) AS sales,
    SUM(sale.invoiced_quantity) AS quantity_sold,
    SUM(sale.profit) AS profit
FROM olap.fact_sale AS sale
JOIN olap.dim_date date USING (date_key)
GROUP BY date.calendar_year, date.month_name, date.fiscal_year, date.fiscal_quarter
ORDER BY date.calendar_year, MIN(date.date_key);

-- 2. Products and product categories by sales and profit.
WITH product_totals AS (
    SELECT
        product.product_category,
        product.product_name,
        SUM(sale.sales) AS sales,
        SUM(sale.profit) AS profit
    FROM olap.fact_sale sale
    JOIN olap.dim_product product USING (product_key)
    GROUP BY product.product_category, product.product_name
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY sales DESC) AS sales_rank,
        ROW_NUMBER() OVER (ORDER BY profit DESC) AS profit_rank
    FROM product_totals
)
SELECT 'Top by sales' AS ranking, product_category, product_name, sales, profit
FROM ranked
WHERE sales_rank <= 10
UNION ALL
SELECT 'Top by profit', product_category, product_name, sales, profit
FROM ranked
WHERE profit_rank <= 10
ORDER BY ranking, sales DESC;

-- 3. Customers and customer categories by revenue.
SELECT
    customer.customer_name,
    customer.customer_category,
    SUM(sale.sales) AS revenue
FROM olap.fact_sale sale
JOIN olap.dim_customer customer USING (customer_key)
GROUP BY customer.customer_id, customer.customer_name, customer.customer_category
ORDER BY revenue DESC
LIMIT 20;

-- 4. Sales and profit by territory, state/province, and city.
WITH geography_sales AS (
    SELECT
        'Territory' AS level,
        customer.sales_territory AS area,
        SUM(sale.sales) AS sales,
        SUM(sale.profit) AS profit
    FROM olap.fact_sale sale
    JOIN olap.dim_customer customer USING (customer_key)
    GROUP BY customer.sales_territory
    UNION ALL
    SELECT
        'State/Province',
        customer.state_province,
        SUM(sale.sales),
        SUM(sale.profit)
    FROM olap.fact_sale sale
    JOIN olap.dim_customer customer USING (customer_key)
    GROUP BY customer.state_province
    UNION ALL
    SELECT
        'City',
        customer.city,
        SUM(sale.sales),
        SUM(sale.profit)
    FROM olap.fact_sale sale
    JOIN olap.dim_customer customer USING (customer_key)
    GROUP BY customer.city
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY level ORDER BY sales DESC) AS rank
    FROM geography_sales
)
SELECT level, area, sales, profit
FROM ranked
WHERE rank <= 10
ORDER BY level, rank;

-- 5. Order value and invoiced sales by salesperson.
WITH order_totals AS (
    SELECT employee_key, SUM(ordered_sales) AS order_value
    FROM olap.fact_order
    GROUP BY employee_key
),
sale_totals AS (
    SELECT employee_key, SUM(sales) AS invoiced_sales
    FROM olap.fact_sale
    GROUP BY employee_key
)
SELECT
    employee.employee_name,
    orders.order_value,
    sales.invoiced_sales
FROM olap.dim_employee employee
LEFT JOIN order_totals orders USING (employee_key)
LEFT JOIN sale_totals sales USING (employee_key)
ORDER BY sales.invoiced_sales DESC;

-- 6. Percentage of ordered quantities later invoiced (matched by order and product).
WITH ordered AS (
    SELECT order_id, product_key, SUM(ordered_quantity) AS quantity_ordered
    FROM olap.fact_order
    GROUP BY order_id, product_key
),
invoiced AS (
    SELECT order_id, product_key, SUM(invoiced_quantity) AS quantity_invoiced
    FROM olap.fact_sale
    WHERE order_id IS NOT NULL
    GROUP BY order_id, product_key
)
SELECT
    SUM(ordered.quantity_ordered) AS quantity_ordered,
    SUM(COALESCE(invoiced.quantity_invoiced, 0)) AS quantity_invoiced,
    ROUND(
        100.0 * SUM(COALESCE(invoiced.quantity_invoiced, 0))
        / NULLIF(SUM(ordered.quantity_ordered), 0),
        2
    ) AS percent_invoiced
FROM ordered
LEFT JOIN invoiced USING (order_id, product_key);

-- 7. Average time from order to invoice, counting each invoice once.
WITH invoices AS (
    SELECT invoice_id, order_id, MAX(days_to_invoice) AS days_to_invoice
    FROM olap.fact_sale
    WHERE order_id IS NOT NULL
    GROUP BY invoice_id, order_id
)
SELECT
    COUNT(*) AS invoices_counted,
    ROUND(AVG(days_to_invoice), 2) AS average_days_to_invoice
FROM invoices;

-- 8. An original order and the linked follow-up backorder order.
-- The follow-up order value is a proxy for the value affected by the backorder.
SELECT
    link.order_id AS original_order_id,
    link.backorder_order_id,
    COUNT(backorder_line.order_line_id) AS backorder_lines,
    SUM(backorder_line.ordered_quantity) AS backorder_quantity,
    SUM(backorder_line.ordered_sales) AS estimated_backorder_value
FROM oltp.order_backorders link
JOIN olap.fact_order backorder_line
  ON backorder_line.order_id = link.backorder_order_id
GROUP BY link.order_id, link.backorder_order_id
ORDER BY estimated_backorder_value DESC;

-- 9. Customer attributes with more than one historical version.
SELECT
    customer_id,
    customer_name,
    COUNT(*) AS versions,
    STRING_AGG(customer_category, ' -> ' ORDER BY effective_start_date) AS category_history
FROM olap.dim_customer
GROUP BY customer_id, customer_name
HAVING COUNT(*) > 1
ORDER BY customer_id;

-- 10. Sales retain the customer category that was valid at invoice time.
SELECT
    customer.customer_id,
    customer.customer_name,
    customer.customer_category,
    customer.effective_start_date,
    customer.effective_end_date,
    customer.is_current,
    SUM(sale.sales) AS sales,
    SUM(sale.profit) AS profit
FROM olap.fact_sale sale
JOIN olap.dim_customer customer USING (customer_key)
WHERE customer.customer_id = 1
GROUP BY
    customer.customer_id,
    customer.customer_name,
    customer.customer_category,
    customer.effective_start_date,
    customer.effective_end_date,
    customer.is_current
ORDER BY customer.effective_start_date;
