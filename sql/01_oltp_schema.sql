-- Small OLTP copy: keep only the source fields used by the sales warehouse.
CREATE SCHEMA IF NOT EXISTS oltp;

-- Geography: city -> state/province -> country.
CREATE TABLE IF NOT EXISTS oltp.countries (
    country_id INTEGER PRIMARY KEY,
    country_name VARCHAR NOT NULL,
    continent VARCHAR,
    region VARCHAR
);

CREATE TABLE IF NOT EXISTS oltp.state_provinces (
    state_province_id INTEGER PRIMARY KEY,
    state_province_name VARCHAR NOT NULL,
    country_id INTEGER NOT NULL REFERENCES oltp.countries(country_id),
    sales_territory VARCHAR
);

CREATE TABLE IF NOT EXISTS oltp.cities (
    city_id INTEGER PRIMARY KEY,
    city_name VARCHAR NOT NULL,
    state_province_id INTEGER NOT NULL REFERENCES oltp.state_provinces(state_province_id)
);

-- Customer and salesperson lookup data.
CREATE TABLE IF NOT EXISTS oltp.customer_categories (
    customer_category_id INTEGER PRIMARY KEY,
    customer_category_name VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS oltp.buying_groups (
    buying_group_id INTEGER PRIMARY KEY,
    buying_group_name VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS oltp.people (
    person_id INTEGER PRIMARY KEY,
    full_name VARCHAR NOT NULL,
    is_salesperson BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS oltp.customers (
    customer_id INTEGER PRIMARY KEY,
    customer_name VARCHAR NOT NULL,
    customer_category_id INTEGER NOT NULL
        REFERENCES oltp.customer_categories(customer_category_id),
    buying_group_id INTEGER REFERENCES oltp.buying_groups(buying_group_id),
    delivery_city_id INTEGER NOT NULL REFERENCES oltp.cities(city_id),
    account_opened_date DATE,
    standard_discount_percentage DECIMAL(9, 4)
);

-- Product and product-category lookup data.
CREATE TABLE IF NOT EXISTS oltp.colors (
    color_id INTEGER PRIMARY KEY,
    color_name VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS oltp.stock_items (
    stock_item_id INTEGER PRIMARY KEY,
    stock_item_name VARCHAR NOT NULL,
    color_id INTEGER REFERENCES oltp.colors(color_id),
    brand VARCHAR,
    size VARCHAR,
    unit_price DECIMAL(18, 2) CHECK (unit_price >= 0)
);

CREATE TABLE IF NOT EXISTS oltp.stock_groups (
    stock_group_id INTEGER PRIMARY KEY,
    stock_group_name VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS oltp.stock_item_stock_groups (
    stock_item_stock_group_id INTEGER PRIMARY KEY,
    stock_item_id INTEGER NOT NULL REFERENCES oltp.stock_items(stock_item_id),
    stock_group_id INTEGER NOT NULL REFERENCES oltp.stock_groups(stock_group_id),
    UNIQUE (stock_item_id, stock_group_id)
);

-- Orders and invoices are separate because their line items have different grains.
CREATE TABLE IF NOT EXISTS oltp.orders (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES oltp.customers(customer_id),
    salesperson_person_id INTEGER NOT NULL REFERENCES oltp.people(person_id),
    order_date DATE NOT NULL,
    is_undersupply_backordered BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS oltp.order_backorders (
    order_id INTEGER PRIMARY KEY REFERENCES oltp.orders(order_id),
    backorder_order_id INTEGER NOT NULL REFERENCES oltp.orders(order_id)
);

CREATE TABLE IF NOT EXISTS oltp.order_lines (
    order_line_id INTEGER PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES oltp.orders(order_id),
    stock_item_id INTEGER NOT NULL REFERENCES oltp.stock_items(stock_item_id),
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    picked_quantity INTEGER NOT NULL CHECK (picked_quantity >= 0),
    unit_price DECIMAL(18, 2) NOT NULL CHECK (unit_price >= 0),
    tax_rate DECIMAL(9, 4) NOT NULL CHECK (tax_rate >= 0)
);

CREATE TABLE IF NOT EXISTS oltp.invoices (
    invoice_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES oltp.customers(customer_id),
    order_id INTEGER REFERENCES oltp.orders(order_id),
    salesperson_person_id INTEGER NOT NULL REFERENCES oltp.people(person_id),
    invoice_date DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS oltp.invoice_lines (
    invoice_line_id INTEGER PRIMARY KEY,
    invoice_id INTEGER NOT NULL REFERENCES oltp.invoices(invoice_id),
    stock_item_id INTEGER NOT NULL REFERENCES oltp.stock_items(stock_item_id),
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    unit_price DECIMAL(18, 2) NOT NULL CHECK (unit_price >= 0),
    tax_rate DECIMAL(9, 4) NOT NULL CHECK (tax_rate >= 0),
    tax_amount DECIMAL(18, 2) NOT NULL,
    line_profit DECIMAL(18, 2) NOT NULL,
    extended_price DECIMAL(18, 2) NOT NULL
);
