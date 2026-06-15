# Pentest 2026-2027 — Security Audit Suite

A single Bash script (`deploy.sh`) that must pass before every production deployment.
It runs three categories of tests: **vulnerability scanning**, **stress testing**, and **DDoS simulation**.

---

## Quick Start

```bash
# 1. Place deploy.sh in your project root (same folder as manage.py and .env)
# 2. Make executable
chmod +x deploy.sh

# 3. Run full audit against local dev server
./deploy.sh http://127.0.0.1:8000

# 4. Run against a staging server, auto-fix safe issues
./deploy.sh https://staging.yourdomain.com --fix

# 5. Scan only — skip stress and DDoS (fast pre-commit check)
./deploy.sh http://127.0.0.1:8000 --skip-stress --skip-ddos

# 6. Full production readiness check with longer test windows
./deploy.sh https://yourdomain.com --duration 60 --threads 100
```

---

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `TARGET_URL` | `http://127.0.0.1:8000` | First positional argument |
| `--fix` | off | Auto-patch: sets `DEBUG=False`, generates new `SECRET_KEY`, fixes `.env` permissions |
| `--skip-stress` | off | Skip all load / stress tests |
| `--skip-ddos` | off | Skip all DDoS simulation tests |
| `--skip-vuln` | off | Skip all vulnerability scans |
| `--report-dir DIR` | `./reports` | Directory to write all report files |
| `--duration N` | `30` | Duration in seconds for each stress/DDoS test |
| `--threads N` | `50` | Concurrent threads for load and DDoS tests |

---

## What Each Test Does

### Vulnerability Scans (checks 0–20)

| # | Check | What is tested |
|---|-------|----------------|
| 0 | Environment / Secrets | `DEBUG`, `SECRET_KEY`, `ALLOWED_HOSTS`, `DB_USER`, password strength, `.env` permissions, git tracking, Ngrok token |
| 1 | Debug Endpoints | `/__debug__/`, `/silk/`, `/_profiler/`, `.env`, `settings.py`, `.git/config` accessibility |
| 2 | Security Headers | `X-Content-Type-Options`, `X-Frame-Options`, `CSP`, `HSTS`, `Referrer-Policy`, `Permissions-Policy`, server version leakage |
| 3 | Admin Panel | Default URL exposure, unauthenticated access, login rate limiting |
| 4 | CSRF | POST without CSRF token rejection, `SameSite=None` without `Secure` |
| 5 | SQL Injection | Error-based and time-based blind SQLi across common parameters; optional sqlmap scan |
| 6 | XSS | Reflected XSS and server-side template injection across common input parameters |
| 7 | Path Traversal | `../../../../etc/passwd`, URL-encoded and double-encoded variants |
| 8 | Open Redirect | `//evil.com`, `https://evil.com` via `next`, `redirect`, `url`, `return` parameters |
| 9 | Command Injection | `;id`, `\|id`, `\$(id)` in common shell-passthrough parameters |
| 10 | SSRF | AWS/GCP metadata endpoints, `file:///etc/passwd`, internal localhost via URL parameters |
| 11 | IDOR | Sequential user/profile/export ID enumeration without authentication |
| 12 | XXE | XML external entity via `file:///etc/passwd` against upload/import endpoints |
| 13 | Auth & Session | Session fixation detection, password reset endpoint, GET-based logout |
| 14 | Cookie Security | `HttpOnly`, `SameSite`, `Secure` flags on all cookies |
| 15 | Sensitive Files | `.env`, `settings.py`, `manage.py`, Docker files, media directories, `.git/config` |
| 16 | Info Disclosure | Debug 404 URL list, stack traces in 500 errors, plaintext emails in source, version headers |
| 17 | TLS / HTTPS | HSTS header, HTTP→HTTPS redirect, weak TLS protocol detection (via nmap) |
| 18 | API Auth | Unauthenticated data access on `/api/`, `/api/v1/`, `/api/users/`, export endpoints |
| 19 | Nikto Scan | Full Nikto web scanner pass (if installed) |
| 20 | Port Scan | nmap fast scan for unexpected open ports (if installed) |

### Stress Tests (checks 21–27)

| # | Test | What is measured |
|---|------|-----------------|
| 21 | Baseline Load (Apache Bench) | RPS, P99 latency, failed requests under `--threads` concurrent users |
| 22 | Spike Test | Server response after `2× --threads` simultaneous requests |
| 23 | Soak Test | Error rate over `--duration` seconds of sustained 2-req/sec load |
| 24 | wrk Benchmark | High-concurrency HTTP/1.1 benchmark (if wrk installed) |
| 25 | Siege Stress | Multi-user simulation (if siege installed) |
| 26 | Large Payload | Server handling of 100KB POST body (should return 413) |
| 27 | Response Stability | Size variance across 10 sequential requests (memory/leak probe) |

### DDoS Simulation (checks 28–35)

| # | Attack | What is simulated |
|---|--------|------------------|
| 28 | HTTP Flood | `--threads` concurrent workers hitting the server with randomised IPs for `--duration` seconds; checks for 429 rate limiting |
| 29 | Cache-Busting Flood | 60 simultaneous requests with unique query strings to bypass CDN/cache |
| 30 | Slowloris | 100–200 slow-drip HTTP connections held open (via slowhttptest or Python); checks server availability after |
| 31 | POST Body Flood | 30 simultaneous 10KB POST requests to login endpoint |
| 32 | SYN / TCP Flood | hping3 SYN flood (root required) or 150-thread TCP connection exhaustion |
| 33 | HTTP/2 Rapid Reset | 200-thread burst of rapid HTTP requests (CVE-2023-44487 simulation) |
| 34 | Brute Force / Credential Stuffing | 25 rapid login attempts; checks for 429/403 blocking |
| 35 | Bandwidth Exhaustion | Response size probe on large export endpoints |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All checks passed (warnings only) — safe to deploy |
| `1` | Failures found — do not deploy until resolved |
| `2` | Critical issues found — do not deploy under any circumstances |

---

## Required Tools

```bash
# Minimum (script will not run without these)
sudo apt-get install curl python3

# Recommended (unlocks more tests)
sudo apt-get install apache2-utils hping3 nmap nikto sqlmap slowhttptest

# Optional benchmarking tools
sudo apt-get install siege
# wrk: https://github.com/wg/wrk (build from source or brew install wrk)
```

---

## Output Files

All reports are written to `./reports/` (or `--report-dir`):

| File | Contents |
|------|----------|
| `security_audit_TIMESTAMP.txt` | Full audit log with pass/fail for every check |
| `vulnerabilities_TIMESTAMP.txt` | Only failures and criticals — share this with developers |
| `stress_results_TIMESTAMP.txt` | Raw output from ab, wrk, siege, soak test |
| `ddos_results_TIMESTAMP.txt` | DDoS simulation results and availability checks |
| `nikto_TIMESTAMP.txt` | Nikto raw output (if nikto installed) |
| `slowloris_TIMESTAMP.html` | slowhttptest report (if installed) |
| `sqlmap_TIMESTAMP/` | sqlmap output directory (if installed) |

---


## Recommended CI/CD Integration

Add to your GitHub Actions or GitLab CI pipeline:

```yaml
# .github/workflows/security.yml
- name: Security Audit
  run: |
    ./deploy.sh http://127.0.0.1:8000 --skip-ddos --duration 15
  # Exits non-zero on failures, blocking the deployment pipeline
```

---

## Legal Notice

> Run these tests **only against systems you own or have explicit written permission to test.**
> The DDoS simulation tests (checks 28–35) generate significant traffic and open many connections.
> Unauthorized use against third-party systems is illegal under the Computer Fraud and Abuse Act (CFAA),
> the UK Computer Misuse Act, and equivalent legislation worldwide.
