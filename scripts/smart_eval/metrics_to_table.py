import csv
import sys
import argparse
from tabulate import tabulate


def parse_metrics_csv(input_csv, output_file):
    with open(input_csv, newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        rows = list(reader)
        if not rows:
            print("No data found in CSV.")
            return
        # Transpose: metrics as rows, values as columns (for each design)
        headers = ["Metric"] + [row["design"] for row in rows]
        metrics = [k for k in rows[0].keys() if k != "design"]
        table = []
        for metric in metrics:
            row = [metric]
            for r in rows:
                row.append(r[metric])
            table.append(row)
        table_str = tabulate(table, headers, tablefmt="grid")
    with open(output_file, "w") as f:
        f.write(table_str)


def main():
    parser = argparse.ArgumentParser(description="Format metrics CSV into a table.")
    parser.add_argument("input_csv", help="Input CSV file path")
    parser.add_argument("output_file", help="Output file path for formatted table")
    args = parser.parse_args()
    parse_metrics_csv(args.input_csv, args.output_file)

if __name__ == "__main__":
    main()
