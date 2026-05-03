#!/bin/bash
# Cluster init script — runs on every node at startup.
# Install extra system/Python dependencies not available via Databricks ML Runtime.

set -euo pipefail

pip install --quiet \
    delta-spark==3.0.0 \
    azure-storage-file-datalake==12.14.0 \
    great-expectations==0.18.12 \
    pyarrow==14.0.2

echo "[init] Libraries installed successfully"
