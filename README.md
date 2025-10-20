# JMeter Performance Testing Sample

This is a ready-to-run JMeter project scaffold designed for API load/stress/spike/soak testing with a **29‑minute bearer token refresh** thread.

## What’s inside
- `jmeter/meritly-perf.jmx` — Test Plan with:
  - setUp thread to get initial token
  - background **Token Refresher** thread (refresh every 29 minutes)
  - **Concurrency Thread Group** for read-heavy endpoints (Agencies, Users)
  - Percent-based **Throughput Controllers**
  - Basic Assertions and Timers
- `data/users.csv` — placeholder for credentials or test data
- `scripts/run-baseline.sh` — CLI run for baseline load
- `scripts/run-stress.sh` — CLI run for step-up stress
- `.github/workflows/jmeter-ci.yml` — optional CI that uploads HTML report artifact
- `.gitignore` — excludes results and reports

## Quick start (local)
1. Install Apache JMeter 5.6.x.
2. Update host and endpoints:
   - Open `jmeter/meritly-perf.jmx` and set:
     - `baseHost` (e.g., `api.example.com`)
     - token endpoint path, and Agencies/Users paths
3. Run baseline:
   ```bash
   bash scripts/run-baseline.sh
   ```
   HTML report will be generated in `report/`.

## Create a new GitHub repo and push

### Option A — GitHub web UI
1. Create an **empty** repository (no README) in your GitHub account, e.g., `meritly-jmeter-perf`.
2. In a terminal:
   ```bash
   cd jmeter-perf-sample
   git init
   git add .
   git commit -m "chore: initial JMeter perf project"
   git branch -M main
   git remote add origin https://github.com/<YOUR_GH_USERNAME>/meritly-jmeter-perf.git
   git push -u origin main
   ```

### Option B — GitHub CLI
```bash
cd jmeter-perf-sample
git init
git add .
git commit -m "chore: initial JMeter perf project"
gh repo create meritly-jmeter-perf --public --source=. --remote=origin --push
```

> If you’d like me to push this into a repo for you, create an empty repo and grant access to the ChatGPT GitHub app, then tell me the **owner/repo** (e.g., `ahmedA/meritly-jmeter-perf`).

## Running different test types
- **Baseline:** `scripts/run-baseline.sh` — steady load at expected peak
- **Stress:** `scripts/run-stress.sh` — stages up every few minutes
- **Spike/Soak:** duplicate a script and tweak `-J` parameters

## Customize
- Change concurrency and timing in the scripts (`-JrampUpSec`, `-JholdSec`, `-JrampDownSec`).
- Adjust **Throughput Controller** percentages for Agencies/Users mix.
- Add more thread groups for write/admin/search flows.