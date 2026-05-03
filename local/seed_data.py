"""Generate sample CSV sales data in local/data/landing/ for local testing."""

import csv
import os
import random
from datetime import date, timedelta

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "data", "landing", "sales")
os.makedirs(OUTPUT_DIR, exist_ok=True)

PRODUCTS  = ["P001", "P002", "P003", "P004", "P005"]
REGIONS   = ["North", "South", "East", "West"]
random.seed(42)

rows = []
start = date(2024, 1, 1)
for i in range(500):
    rows.append({
        "sale_id":    f"S{i+1:05d}",
        "product_id": random.choice(PRODUCTS),
        "region":     random.choice(REGIONS),
        "amount":     round(random.uniform(10.0, 500.0), 2),
        "quantity":   random.randint(1, 20),
        "sale_date":  (start + timedelta(days=random.randint(0, 364))).isoformat(),
    })

# Sprinkle intentional quality issues
rows[5]["amount"]   = None   # null
rows[10]["sale_id"] = rows[9]["sale_id"]  # duplicate
rows[20]["region"]  = "  east  "  # dirty whitespace

out_file = os.path.join(OUTPUT_DIR, "sales_2024.csv")
with open(out_file, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {len(rows)} rows -> {out_file}")
