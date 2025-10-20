#!/usr/bin/env bash
set -euo pipefail

JMETER_BIN="${JMETER_BIN:-jmeter}"

# Params (override with -Jkey=value on CLI)
: "${baseHost:=api.example.com}"
: "${rampUpSec:=300}"
: "${holdSec:=1800}"
: "${rampDownSec:=120}"
: "${token_refresh_sec:=1740}"

mkdir -p results report
"${JMETER_BIN}" -n -t jmeter/meritly-perf.jmx   -JbaseHost="${baseHost}"   -JrampUpSec="${rampUpSec}"   -JholdSec="${holdSec}"   -JrampDownSec="${rampDownSec}"   -Jtoken_refresh_sec="${token_refresh_sec}"   -l results/baseline.jtl

"${JMETER_BIN}" -g results/baseline.jtl -o report/baseline_html
echo "Baseline complete. Open report/baseline_html/index.html"