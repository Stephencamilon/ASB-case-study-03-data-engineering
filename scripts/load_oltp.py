from pathlib import Path

import duckdb


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "archive"
DATABASE = ROOT / "data" / "wwi_case_study.duckdb"

# Each entry is: OLTP table, source CSV, source columns to keep.
# Load lookup tables before transactions so the foreign keys can be checked.
LOADS = [
    ("countries", "Application/Application.Countries.csv", "CountryID, CountryName, Continent, Region"),
    ("state_provinces", "Application/Application.StateProvinces.csv", "StateProvinceID, StateProvinceName, CountryID, SalesTerritory"),
    ("cities", "Application/Application.Cities.csv", "CityID, CityName, StateProvinceID"),
    ("people", "Application/Application.People.csv", "PersonID, FullName, IsSalesperson::BOOLEAN"),
    ("customer_categories", "Sales/Sales.CustomerCategories.csv", "CustomerCategoryID, CustomerCategoryName"),
    ("buying_groups", "Sales/Sales.BuyingGroups.csv", "BuyingGroupID, BuyingGroupName"),
    ("colors", "Warehouse/Warehouse.Colors.csv", "ColorID, ColorName"),
    ("stock_groups", "Warehouse/Warehouse.StockGroups.csv", "StockGroupID, StockGroupName"),
    ("stock_items", "Warehouse/Warehouse.StockItems.csv", "StockItemID, StockItemName, ColorID, Brand, Size, UnitPrice"),
    ("stock_item_stock_groups", "Warehouse/Warehouse.StockItemStockGroups.csv", "StockItemStockGroupID, StockItemID, StockGroupID"),
    ("customers", "Sales/Sales.Customers.csv", "CustomerID, CustomerName, CustomerCategoryID, BuyingGroupID, DeliveryCityID, AccountOpenedDate, StandardDiscountPercentage"),
    ("orders", "Sales/Sales.Orders.csv", "OrderID, CustomerID, SalespersonPersonID, OrderDate, IsUndersupplyBackordered::BOOLEAN"),
    ("order_backorders", "Sales/Sales.Orders.csv", "OrderID, BackorderOrderID"),
    ("order_lines", "Sales/Sales.OrderLines.csv", "OrderLineID, OrderID, StockItemID, Quantity, PickedQuantity, UnitPrice, TaxRate"),
    ("invoices", "Sales/Sales.Invoices.csv", "InvoiceID, CustomerID, OrderID, SalespersonPersonID, InvoiceDate"),
    ("invoice_lines", "Sales/Sales.InvoiceLines.csv", "InvoiceLineID, InvoiceID, StockItemID, Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice"),
]


def main() -> None:
    missing_files = [
        source for _, source, _ in LOADS
        if not (ARCHIVE / source).is_file()
    ]
    if missing_files:
        raise FileNotFoundError(f"Missing CSV files: {', '.join(sorted(set(missing_files)))}")

    DATABASE.parent.mkdir(exist_ok=True)
    connection = duckdb.connect(str(DATABASE))
    try:
        connection.execute("BEGIN TRANSACTION")
        try:
            # Rebuild the source snapshot so rerunning never appends duplicate rows.
            connection.execute("DROP SCHEMA IF EXISTS oltp CASCADE")
            schema = (ROOT / "sql" / "01_oltp_schema.sql").read_text(encoding="utf-8")
            connection.execute(schema)

            for table, source, columns in LOADS:
                path = str((ARCHIVE / source).resolve()).replace("'", "''")
                filter_rows = (
                    "WHERE BackorderOrderID IS NOT NULL"
                    if table == "order_backorders"
                    else ""
                )
                connection.execute(
                    f"""
                    INSERT INTO oltp.{table}
                    SELECT {columns}
                    FROM read_csv_auto('{path}', delim=';', nullstr='NULL')
                    {filter_rows}
                    """
                )

            connection.execute("COMMIT")
        except Exception:
            connection.execute("ROLLBACK")
            raise

        print(f"Loaded OLTP snapshot into {DATABASE}")
        for table, _, _ in LOADS:
            count = connection.execute(
                f"SELECT COUNT(*) FROM oltp.{table}"
            ).fetchone()[0]
            print(f"{table}: {count:,} rows")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
