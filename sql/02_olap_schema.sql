CREATE SCHEMA IF NOT EXISTS olap;

-- Four dimensions describe when, who, where, and what.
CREATE TABLE IF NOT EXISTS olap.dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    month_name VARCHAR NOT NULL,
    calendar_year SMALLINT NOT NULL,
    fiscal_month SMALLINT NOT NULL,
    fiscal_quarter SMALLINT NOT NULL,
    fiscal_year SMALLINT NOT NULL
);

-- Customer and their delivery location are together to keep the model small.
-- The effective dates support the required customer SCD Type 2 history.
CREATE TABLE IF NOT EXISTS olap.dim_customer (
    customer_key BIGINT PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    customer_name VARCHAR NOT NULL,
    customer_category VARCHAR NOT NULL,
    buying_group VARCHAR,
    city VARCHAR NOT NULL,
    state_province VARCHAR NOT NULL,
    country VARCHAR NOT NULL,
    sales_territory VARCHAR,
    effective_start_date DATE NOT NULL,
    effective_end_date DATE NOT NULL,
    is_current BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS olap.dim_employee (
    employee_key BIGINT PRIMARY KEY,
    person_id INTEGER NOT NULL UNIQUE,
    employee_name VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS olap.dim_product (
    product_key BIGINT PRIMARY KEY,
    stock_item_id INTEGER NOT NULL UNIQUE,
    product_name VARCHAR NOT NULL,
    product_category VARCHAR,
    brand VARCHAR
);

-- One row per order line.
CREATE TABLE IF NOT EXISTS olap.fact_order (
    order_line_id INTEGER PRIMARY KEY,
    order_id INTEGER NOT NULL,
    date_key INTEGER NOT NULL REFERENCES olap.dim_date(date_key),
    customer_key BIGINT NOT NULL REFERENCES olap.dim_customer(customer_key),
    employee_key BIGINT NOT NULL REFERENCES olap.dim_employee(employee_key),
    product_key BIGINT NOT NULL REFERENCES olap.dim_product(product_key),
    ordered_quantity INTEGER NOT NULL,
    picked_quantity INTEGER NOT NULL,
    ordered_sales DECIMAL(18, 2) NOT NULL,
    is_backordered BOOLEAN NOT NULL
);

-- One row per invoice line.
CREATE TABLE IF NOT EXISTS olap.fact_sale (
    invoice_line_id INTEGER PRIMARY KEY,
    invoice_id INTEGER NOT NULL,
    order_id INTEGER,
    date_key INTEGER NOT NULL REFERENCES olap.dim_date(date_key),
    customer_key BIGINT NOT NULL REFERENCES olap.dim_customer(customer_key),
    employee_key BIGINT NOT NULL REFERENCES olap.dim_employee(employee_key),
    product_key BIGINT NOT NULL REFERENCES olap.dim_product(product_key),
    invoiced_quantity INTEGER NOT NULL,
    sales DECIMAL(18, 2) NOT NULL,
    profit DECIMAL(18, 2) NOT NULL,
    days_to_invoice INTEGER
);
