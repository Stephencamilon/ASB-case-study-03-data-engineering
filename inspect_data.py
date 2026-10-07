import duckdb

con = duckdb.connect()

file_path = "archive/Sales/Sales.Customers.csv"

files = {
    "customers": "archive/Sales/Sales.Customers.csv",
    "orders": "archive/Sales/Sales.Orders.csv",
    "order_lines": "archive/Sales/Sales.OrderLines.csv",
    "invoices": "archive/Sales/Sales.Invoices.csv",
    "invoice_lines": "archive/Sales/Sales.InvoiceLines.csv",
    "people": "archive/Application/Application.People.csv",
    "cities": "archive/Application/Application.Cities.csv",
    "state_provinces": "archive/Application/Application.StateProvinces.csv",
    "countries": "archive/Application/Application.Countries.csv",
    "customer_categories": "archive/Sales/Sales.CustomerCategories.csv",
    "buying_groups": "archive/Sales/Sales.BuyingGroups.csv",
    "stock_items": "archive/Warehouse/Warehouse.StockItems.csv",
    "colors": "archive/Warehouse/Warehouse.Colors.csv",
    "package_types": "archive/Warehouse/Warehouse.PackageTypes.csv",
}

for name, path in files.items():
    print(f"\n{'=' * 60}")
    print(name.upper())
    print(f"{'=' * 60}")

    result = con.execute(
        f"""
        SELECT *
        FROM read_csv_auto('{path}')
        LIMIT 3
        """
    ).df()

    print("Columns:")
    print(list(result.columns))

    print("\nSample:")
    print(result)