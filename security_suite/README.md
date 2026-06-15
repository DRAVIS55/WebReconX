# University Timetable System — Security Audit Suite

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

## Vulnerabilities Found During Pre-Production Testing

The following were discovered in the October 2025 pre-production test run:

### Critical
1. **`DEBUG=True` in production** — debug toolbar pages (`/__debug__/`, `/silk/`) exposed `SECRET_KEY`, database credentials, SQL queries, and all URL patterns to unauthenticated users.
2. **Insecure `SECRET_KEY`** — default `django-insecure-` prefix; session cookies and CSRF tokens could be forged.
3. **`.env` committed to git** — `DB_PASSWORD`, `EMAIL_HOST_PASSWORD`, and `NGROK_AUTHTOKEN` all in version history.
4. **`NGROK_AUTHTOKEN` in use** — Ngrok tunnel bypassed firewall, exposing the app on a public URL with no DDoS protection.

### High
5. **`DB_USER=root`** — application connected to the database as the superuser.
6. **Media directory accessible** — `/media/notifications/` served confidential PDF reports (timetable feasibility, COD reports) to unauthenticated users.
7. **No admin login rate limiting** — 30+ brute-force attempts against `/admin/login/` went unblocked.
8. **Staff email addresses scraped** — `info@chuka.ac.ke` visible in plain HTML source.

### Medium
9. **Server header leaks stack** — `WSGIServer/0.2 CPython/3.13.7` disclosed in every response.
10. **No HTTPS enforcement** — app running over HTTP via Ngrok with no TLS termination.
11. **Media directory browsable** — no `autoindex off` protection.

---

## Fixing the Issues Found

### Immediate (before any deployment)

```bash
# 1. Disable DEBUG
sed -i 's/^DEBUG=True/DEBUG=False/' .env

# 2. Rotate SECRET_KEY
python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
# Paste output into .env as SECRET_KEY=<new value>

# 3. Remove .env from git
git rm --cached .env
echo ".env" >> .gitignore
git commit -m "Remove .env from version control"

# 4. Lock .env permissions
chmod 600 .env

# 5. Create a least-privilege DB user
# In MySQL/MariaDB:
# CREATE USER 'timetable_app'@'localhost' IDENTIFIED BY '<strong-password>';
# GRANT SELECT, INSERT, UPDATE, DELETE ON timetable_db.* TO 'timetable_app'@'localhost';
```

### Before Production Deployment

```python
# settings.py — add these security settings
SECURE_SSL_REDIRECT = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'
SESSION_COOKIE_SECURE = True
SESSION_COOKIE_HTTPONLY = True
CSRF_COOKIE_SECURE = True
SECURE_REFERRER_POLICY = 'same-origin'
```

```python
# settings.py — add django-axes for brute force protection
# pip install django-axes
INSTALLED_APPS += ['axes']
MIDDLEWARE = ['axes.middleware.AxesMiddleware'] + MIDDLEWARE
AUTHENTICATION_BACKENDS = ['axes.backends.AxesStandaloneBackend', 'django.contrib.auth.backends.ModelBackend']
AXES_FAILURE_LIMIT = 5
AXES_COOLOFF_TIME = 1  # hours
```

```nginx
# nginx.conf — production configuration
server {
    listen 443 ssl http2;
    server_tokens off;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    location /login/ {
        limit_req zone=login burst=5 nodelay;
        proxy_pass http://127.0.0.1:8000;
    }

    location /admin/ {
        allow YOUR_OFFICE_IP;
        deny all;
        proxy_pass http://127.0.0.1:8000;
    }

    # Block sensitive files
    location ~* \.(env|log|py|cfg|ini|conf|bak|sql|sh)$ { deny all; }
    location ~ /\.git { deny all; }

    # Slowloris mitigation
    client_header_timeout 10s;
    client_body_timeout 10s;
    keepalive_timeout 15s;

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'";
}
```

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
