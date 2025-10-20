High-level test strategy

Smoke: sanity checks (few users, short time) to verify endpoints & token flow.

Baseline load: expected normal traffic pattern (hit your SLOs here).

Stress: ramp beyond baseline to find the knee point (where errors/latency spike).

Spike: sudden traffic burst to test autoscaling & caching.

Soak: hours-long steady load to surface memory leaks/slow creep (token refresh runs here).

Test Plan structure (tree)
Test Plan
  + User Defined Variables
      baseProtocol = https
      baseHost     = api.example.com
      basePort     = 443
      token_ttl_sec        = 1800         # 30 min
      token_refresh_sec    = 1740         # 29 min
      rampUpSec            = 300
      holdSec              = 1800
      rampDownSec          = 120
      csv_users_path       = data/users.csv
  + HTTP Request Defaults (protocol/host/port, path blank)
  + HTTP Cookie Manager
  + HTTP Cache Manager
  + DNS Cache Manager
  + HTTP Header Manager (shared)
      Accept: application/json
      Content-Type: application/json
      Authorization: Bearer ${__property(auth.token)}   # filled by token thread
  + CSV Data Set Config (optional)
      Filename: ${csv_users_path}
      Variable Names: username,password
      Recycle on EOF: true
      Stop thread on EOF: false
      Sharing mode: all threads

  # 1) setUp: sanity + warm token
  + setUp Thread Group (1 thread, loop 1)
      + Generate Initial Token (HTTP Request -> /oauth/token or your auth endpoint)
      + JSON Extractor:
          access_token  = $.access_token
          expires_in    = $.expires_in
      + JSR223 PostProcessor (Groovy):
          props.put("auth.token", vars.get("access_token"))
      + Response Assertions (200, has access_token)

  # 2) Token refresher: runs the whole test in background
  + Thread Group: Token Refresher (1 thread, Loop: forever; Scheduler: on; Duration = total test duration + 120s)
      + Runtime Controller (optional cap, e.g., 8h)
          + If Controller (first run: sleep small)
              Condition: ${__groovy(props.get('auth.token')==null)}
              + HTTP Request -> /oauth/token  (same as above)
              + JSON Extractor (access_token)
              + JSR223 PostProcessor (props.put("auth.token", vars.get("access_token")))
          + While Controller (true)
              + Flow Control Action (Pause)  # Wait ~29 minutes between refreshes
                  Pause (ms): ${__intSum(${token_refresh_sec},0)}000
              + HTTP Request -> /oauth/token (grant_type=refresh_token or client_credentials)
              + JSON Extractor (access_token)
              + JSR223 PostProcessor (props.put("auth.token", vars.get("access_token")))
              + If Controller (retry on failure)
                  Condition: ${JMeterThread.last_sample_ok} == false
                  + Flow Control Action (Pause 5s)
                  + HTTP Request -> /oauth/token (retry)
                  + JSON Extractor + JSR223 PostProcessor again

  # 3) Business scenarios – use Concurrency Thread Group (Plugins)
  + Concurrency Thread Group: Read-heavy APIs
      Target Concurrency: 100
      Ramp-up Time (sec): ${rampUpSec}
      Hold Target Rate (sec): ${holdSec}
      Ramp-down Time (sec): ${rampDownSec}
      + Uniform Random Timer (1000–3000 ms)
      + Throughput Controller (Percent Execution = 60) "Agencies flow"
          + Transaction Controller "GET /agencies"
              + HTTP Request GET /agencies?size=50&page=${__Random(1,10)}
              + JSON Assertion (e.g., $.content exists)
              + Duration Assertion (e.g., < 800ms)
      + Throughput Controller (Percent Execution = 40) "Users flow"
          + Transaction Controller "GET /users"
              + HTTP Request GET /users?active=true&page=${__Random(1,10)}
              + JSON Assertion (e.g., $.items exists)
              + Duration Assertion (e.g., < 800ms)
      + If Controller (token expired guard)
          Condition: ${__groovy(prev.getResponseCode()=='401')}
          + HTTP Request -> /oauth/token (instant refresh fallback)
          + JSR223 PostProcessor -> props.put("auth.token", vars.get("access_token"))
          + Flow Control Action (Pause 500 ms)
          + GoTo (re-try last request) [or just rely on user loop]

  # Optional: additional scenario groups
  + Concurrency Thread Group: Write/modify APIs (lower % mix)
  + Concurrency Thread Group: Search-heavy APIs
  + Concurrency Thread Group: Admin paths (small concurrency)

  # 4) tearDown: cleanup/metrics
  + tearDown Thread Group
      + (Optional) Hit a health endpoint, dump counters, or stop background jobs

  # Listeners (keep lightweight during run)
  + Simple Data Writer (JTL to disk)
  + Backend Listener (InfluxDB/Prometheus)  # for Grafana dashboards
  + View Results Tree (disabled in CI)

Why this layout works

Token safety: a dedicated Token Refresher thread writes auth.token to JMeter properties, which every request reads via the Header Manager (Authorization: Bearer ${__property(auth.token)}). This decouples business traffic from auth timing and guarantees refresh every ~29 minutes, plus a fast 401 guard for edge cases/clock skew.

Realistic traffic mix: Throughput Controllers (Percent Execution) inside each business thread group give you stable per-scenario weights (e.g., Agencies 60% / Users 40%).

Pacing: a Uniform Random Timer gives human-like think time; adjust for your RPS target. If you need precise RPS shaping, add the Throughput Shaping Timer + Concurrency Thread Group.

Observability: Transaction Controllers measure per-flow latency; Assertions keep SLOs honest; Backend Listener streams time series to Grafana while JTL captures raw details for the HTML report.

Test types (how to run each)

Smoke: Concurrency = 1–5, Hold 2–5 min. Validates token, headers, JSON shape, 200s.

Baseline Load: Concurrency = expected peak (e.g., 100), RampUp 5–10 min, Hold 30–60 min. Exit criteria: error rate < 1%, p95 latency within SLO.

Stress: Use Stepping Thread Group or stage the Concurrency Thread Group (e.g., 50 → 100 → 150 → 200 every 10–15 min). Stop when p95/p99 or error rate crosses threshold: that’s your capacity knee.

Spike: Start at 20, jump to 200 in 10–20 sec, hold 2–5 min, drop to 20. Watch for 5xx, queueing, cold starts.

Soak: Same as baseline but 4–8 hours. Token refresher keeps it alive. Monitor memory/CPU, error creep, GC pauses.

Key implementation details
1) Capturing & sharing the token

JSON Extractor on the token response:

Names: access_token

JSONPath: $.access_token

JSR223 PostProcessor (Groovy) right under the token sampler:

props.put('auth.token', vars.get('access_token'))


Header Manager for all business samplers:

Authorization: Bearer ${__property(auth.token)}

2) Refresh loop (29 minutes)

In the Token Refresher thread group:

Add Flow Control Action (Pause) with ${token_refresh_sec}000 ms.

Then call your token endpoint again, extract, and props.put(...) the new token.

Add a quick retry If Controller if the refresh fails transiently.

Tip: Many IdPs set tokens to 30 min but allow refresh a bit earlier; 29 min is smart. If you see occasional 401s due to clock skew, drop to 25–27 min.

3) Guarding business calls (401 fallback)

Place an If Controller after key API samplers:

Condition: ${__groovy(prev.getResponseCode()=='401')}
  -> Token request
  -> Extract + props.put(...)
  -> (Optional) Flow Control Pause 500ms
  -> Re-issue the last API (or let next loop try)

4) Data & correlation

Put dynamic inputs in CSV Data Set Config (usernames, IDs, org codes).

Use JSON/JMESPath Extractors to capture IDs from one call and feed the next.

Use Regex/JSON Assertion for shape & business rules.

5) Accuracy & cleanliness

Disable heavy listeners during real runs (use Simple Data Writer + Backend Listener).

Keep View Results Tree only for local debugging.

Generate HTML report after run:

jmeter -n -t test.jmx -l results.jtl -e -o report_dir

6) Scripting & CI

Parameterize via -J flags:

jmeter -n -t test.jmx \
  -JbaseHost=api.example.com \
  -JrampUpSec=300 -JholdSec=1800 -JrampDownSec=120 \
  -Jtoken_refresh_sec=1740 \
  -l results.jtl


Consider a Taurus (bzt) YAML wrapper later for readable scenarios and CI integration, but you can start with pure JMeter as above.

Practical “starter” percentages & targets

Read-heavy group: Agencies 60%, Users 40%

Write group (if applicable): Create 20%, Update 30%, Delete 5%, Read 45%

SLOs (example): p95 < 800 ms for reads, < 1200 ms for writes; error < 1%

Common pitfalls (so you avoid them)

Putting form params in Params vs. Body incorrectly: For application/x-www-form-urlencoded, use Body Data with the right Header; don’t double-encode.

Token stored in vars (thread-local): store in props so all threads can read it.

No pacing: without timers you’ll overshoot capacity. Use Uniform Random Timer or Throughput Shaping Timer.

Big listeners: they kill throughput. Keep them off in load runs.

Cache/Cookies missing: many APIs rely on them; include Cookie & Cache Managers.