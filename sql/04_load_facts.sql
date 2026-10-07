-- Refresh facts so they use the latest dimension keys.
CREATE OR REPLACE TABLE olap.fact_order AS
SELECT
    line.order_line_id,
    orders.order_id,
    date.date_key,
    customer.customer_key,
    employee.employee_key,
    product.product_key,
    line.quantity AS ordered_quantity,
    line.picked_quantity,
    line.quantity * line.unit_price AS ordered_sales,
    backorder.backorder_order_id IS NOT NULL AS is_backordered
FROM oltp.order_lines line
JOIN oltp.orders orders USING (order_id)
JOIN oltp.customers source_customer USING (customer_id)
JOIN olap.dim_date date ON date.full_date = orders.order_date
JOIN olap.dim_customer customer
  ON customer.customer_id = source_customer.customer_id
 AND orders.order_date BETWEEN customer.effective_start_date AND customer.effective_end_date
JOIN olap.dim_employee employee ON employee.person_id = orders.salesperson_person_id
JOIN olap.dim_product product USING (stock_item_id)
LEFT JOIN oltp.order_backorders backorder USING (order_id);

CREATE OR REPLACE TABLE olap.fact_sale AS
SELECT
    line.invoice_line_id,
    invoice.invoice_id,
    invoice.order_id,
    date.date_key,
    customer.customer_key,
    employee.employee_key,
    product.product_key,
    line.quantity AS invoiced_quantity,
    line.extended_price - line.tax_amount AS sales,
    line.line_profit AS profit,
    CASE WHEN orders.order_date IS NOT NULL
         THEN date_diff('day', orders.order_date, invoice.invoice_date)
    END AS days_to_invoice
FROM oltp.invoice_lines line
JOIN oltp.invoices invoice USING (invoice_id)
JOIN oltp.customers source_customer ON source_customer.customer_id = invoice.customer_id
JOIN olap.dim_date date ON date.full_date = invoice.invoice_date
JOIN olap.dim_customer customer
  ON customer.customer_id = source_customer.customer_id
 AND invoice.invoice_date BETWEEN customer.effective_start_date AND customer.effective_end_date
JOIN olap.dim_employee employee ON employee.person_id = invoice.salesperson_person_id
JOIN olap.dim_product product USING (stock_item_id)
LEFT JOIN oltp.orders orders ON orders.order_id = invoice.order_id;
