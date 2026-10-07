"""Run the simplified sales case-study pipeline from start to finish."""

import csv
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DATABASE = ROOT / "data" / "wwi_case_study.duckdb"
RESULTS = ROOT / "results"
SQL = ROOT / "sql"

sys.path.insert(0, str(ROOT / "scripts"))
from load_oltp import ARCHIVE, LOADS, main as load_oltp  # noqa: E402


def run_sql(connection: duckdb.DuckDBPyConnection, filename: str) -> None:
    connection.execute((SQL / filename).read_text(encoding="utf-8"))
    print(f"Completed {filename}")


def save_business_results(connection: duckdb.DuckDBPyConnection) -> None:
    RESULTS.mkdir(exist_ok=True)
    queries = [
        query.strip()
        for query in (SQL / "06_business_questions.sql")
        .read_text(encoding="utf-8")
        .split(";")
        if query.strip()
    ]

    for number, query in enumerate(queries, start=1):
        result = connection.execute(query)
        with (RESULTS / f"business_q{number:02}.csv").open(
            "w", newline="", encoding="utf-8"
        ) as output:
            writer = csv.writer(output)
            writer.writerow([column[0] for column in result.description])
            writer.writerows(result.fetchall())

    print(f"Saved {len(queries)} business-question results in {RESULTS}")


def main() -> None:
    log_lines = []

    def record(message: str) -> None:
        print(message)
        log_lines.append(message)

    missing_files = [
        source for _, source, _ in LOADS if not (ARCHIVE / source).is_file()
    ]
    if missing_files:
        raise FileNotFoundError(
            f"Missing source files: {', '.join(sorted(set(missing_files)))}"
        )

    # This is a generated file, so start from a clean copy on every run.
    if DATABASE.exists():
        DATABASE.unlink()

    record("1/5 Loading source CSVs")
    load_oltp()
    log_lines.append("CSV-to-OLTP load completed.")

    record("OLTP source row counts:")
    connection = duckdb.connect(str(DATABASE))
    try:
        for table, _, _ in LOADS:
            count = connection.execute(
                f"SELECT COUNT(*) FROM oltp.{table}"
            ).fetchone()[0]
            record(f"  oltp.{table}: {count:,}")

        record("2/5 Creating warehouse tables")
        run_sql(connection, "02_olap_schema.sql")
        log_lines.append("Completed 02_olap_schema.sql")
        run_sql(connection, "03_load_dimensions.sql")
        log_lines.append("Completed 03_load_dimensions.sql")

        record("3/5 Demonstrating customer history")
        run_sql(connection, "05_demo_customer_scd.sql")
        log_lines.append("Completed 05_demo_customer_scd.sql")

        record("4/5 Loading order and invoice facts")
        run_sql(connection, "04_load_facts.sql")
        log_lines.append("Completed 04_load_facts.sql")

        record("5/5 Saving business-question results")
        save_business_results(connection)

        record("Warehouse row counts:")
        row_counts = {}
        for table in (
            "dim_date",
            "dim_customer",
            "dim_employee",
            "dim_product",
            "fact_order",
            "fact_sale",
        ):
            count = connection.execute(
                f"SELECT COUNT(*) FROM olap.{table}"
            ).fetchone()[0]
            row_counts[table] = count
            record(f"  {table}: {count:,}")

        current_version_errors = connection.execute(
            """
            SELECT COUNT(*)
            FROM (
                SELECT customer_id
                FROM olap.dim_customer
                GROUP BY customer_id
                HAVING SUM(is_current::INTEGER) <> 1
            )
            """
        ).fetchone()[0]
        date_range_errors = connection.execute(
            """
            SELECT COUNT(*)
            FROM olap.dim_customer
            WHERE effective_start_date > effective_end_date
            """
        ).fetchone()[0]
        order_fact_matches = row_counts["fact_order"] == connection.execute(
            "SELECT COUNT(*) FROM oltp.order_lines"
        ).fetchone()[0]
        sale_fact_matches = row_counts["fact_sale"] == connection.execute(
            "SELECT COUNT(*) FROM oltp.invoice_lines"
        ).fetchone()[0]
        customer_1_versions = connection.execute(
            "SELECT COUNT(*) FROM olap.dim_customer WHERE customer_id = 1"
        ).fetchone()[0]
        historical_sales = connection.execute(
            """
            SELECT COUNT(DISTINCT customer_key)
            FROM olap.fact_sale sale
            JOIN olap.dim_customer customer USING (customer_key)
            WHERE customer.customer_id = 1
            """
        ).fetchone()[0]
        duplicate_fact_ids = connection.execute(
            """
            SELECT
                (SELECT COUNT(*) FROM (
                    SELECT order_line_id
                    FROM olap.fact_order
                    GROUP BY order_line_id
                    HAVING COUNT(*) > 1
                ))
                +
                (SELECT COUNT(*) FROM (
                    SELECT invoice_line_id
                    FROM olap.fact_sale
                    GROUP BY invoice_line_id
                    HAVING COUNT(*) > 1
                ))
            """
        ).fetchone()[0]
        unresolved_fact_keys = connection.execute(
            """
            SELECT
                (SELECT COUNT(*)
                 FROM olap.fact_order f
                 LEFT JOIN olap.dim_date d USING (date_key)
                 LEFT JOIN olap.dim_customer c USING (customer_key)
                 LEFT JOIN olap.dim_employee e USING (employee_key)
                 LEFT JOIN olap.dim_product p USING (product_key)
                 WHERE d.date_key IS NULL OR c.customer_key IS NULL
                    OR e.employee_key IS NULL OR p.product_key IS NULL)
                +
                (SELECT COUNT(*)
                 FROM olap.fact_sale f
                 LEFT JOIN olap.dim_date d USING (date_key)
                 LEFT JOIN olap.dim_customer c USING (customer_key)
                 LEFT JOIN olap.dim_employee e USING (employee_key)
                 LEFT JOIN olap.dim_product p USING (product_key)
                 WHERE d.date_key IS NULL OR c.customer_key IS NULL
                    OR e.employee_key IS NULL OR p.product_key IS NULL)
            """
        ).fetchone()[0]
        invalid_values = connection.execute(
            """
            SELECT
                (SELECT COUNT(*) FROM oltp.order_lines
                 WHERE quantity < 0 OR picked_quantity < 0
                    OR picked_quantity > quantity OR unit_price < 0 OR tax_rate < 0)
                +
                (SELECT COUNT(*) FROM oltp.invoice_lines
                 WHERE quantity < 0 OR unit_price < 0 OR tax_rate < 0
                    OR tax_amount < 0 OR extended_price < 0)
            """
        ).fetchone()[0]
        invalid_invoice_dates = connection.execute(
            """
            SELECT COUNT(*)
            FROM oltp.invoices invoice
            JOIN oltp.orders orders USING (order_id)
            WHERE invoice.invoice_date < orders.order_date
            """
        ).fetchone()[0]
        overlapping_customer_versions = connection.execute(
            """
            SELECT COUNT(*)
            FROM olap.dim_customer first_version
            JOIN olap.dim_customer second_version
              ON first_version.customer_id = second_version.customer_id
             AND first_version.customer_key < second_version.customer_key
             AND first_version.effective_start_date <= second_version.effective_end_date
             AND second_version.effective_start_date <= first_version.effective_end_date
            """
        ).fetchone()[0]

        checks = {
            "Order fact row count matches source lines": order_fact_matches,
            "Sale fact row count matches source lines": sale_fact_matches,
            "Fact line identifiers are unique": duplicate_fact_ids == 0,
            "Fact dimension keys resolve": unresolved_fact_keys == 0,
            "Source quantities and amounts are valid": invalid_values == 0,
            "Invoice dates do not precede order dates": invalid_invoice_dates == 0,
            "Each customer has one current dimension version": current_version_errors == 0,
            "Customer SCD date ranges are valid": date_range_errors == 0,
            "Customer SCD date ranges do not overlap": overlapping_customer_versions == 0,
            "Customer SCD example has two versions": customer_1_versions == 2,
            "Sales use both customer versions": historical_sales == 2,
        }
        for label, passed in checks.items():
            if not passed:
                raise ValueError(f"Data-quality check failed: {label}")
            record(f"PASS: {label}")
    finally:
        connection.close()

    record(f"Pipeline completed: {DATABASE}")
    (RESULTS / "pipeline_log.txt").write_text(
        "\n".join(log_lines) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
