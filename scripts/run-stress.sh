#!/usr/bin/env bash
set -euo pipefail
JMETER_BIN="${JMETER_BIN:-jmeter}"

: "${baseHost:=api.example.com}"
: "${token_refresh_sec:=1740}"

mkdir -p results report

# You can duplicate the test plan with different params, or use the same JMX and vary -J values:
"${JMETER_BIN}" -n -t jmeter/meritly-perf.jmx   -JbaseHost="${baseHost}"   -JrampUpSec=120   -JholdSec=600   -JrampDownSec=60   -Jtoken_refresh_sec="${token_refresh_sec}"   -l results/stress.jtl

"${JMETER_BIN}" -g results/stress.jtl -o report/stress_html
echo "Stress complete. Open report/stress_html/index.html"