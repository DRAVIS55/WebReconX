#!/bin/bash

# ============================================================
# University Timetable System — Full Security Audit Suite
# ============================================================
# Covers:
#   - Environment / secrets hardening checks
#   - HTTP security header validation
#   - Vulnerability scanning (SQLi, XSS, CSRF, path traversal,
#     open redirect, command injection, IDOR, SSRF, XXE)
#   - Authentication & session security
#   - Stress testing (load, spike, soak)
#   - DDoS simulation (SYN flood, HTTP flood, Slowloris,
#     HTTP/2 rapid reset, cache-busting, brute force)
#   - Brute-force resistance
#   - Information disclosure
#   - API & admin security
#   - Media / static file exposure
#   - TLS / HTTPS enforcement
#
# Usage:
#   ./deploy.sh [TARGET_URL] [OPTIONS]
#
# Options:
#   --fix            Auto-patch safe issues (.env, permissions)
#   --skip-stress    Skip load / stress tests
#   --skip-ddos      Skip DDoS simulation tests
#   --skip-vuln      Skip vulnerability scans
#   --report-dir DIR Write reports to DIR (default: ./reports)
#   --duration N     Stress/DDoS test duration in seconds (default: 30)
#   --threads N      Concurrent threads for stress tests (default: 50)
#
# Examples:
#   ./deploy.sh http://127.0.0.1:8000
#   ./deploy.sh https://yourapp.pythonanywhere.com --skip-ddos
#   ./deploy.sh http://127.0.0.1:8000 --fix --duration 60 --threads 100
#
# Requirements (auto-checked):
#   curl, python3, ab (apache2-utils), wrk or siege (optional),
#   hping3 (optional, needs root for SYN flood),
#   slowhttptest (optional), nmap (optional), nikto (optional)
# ============================================================

TARGET=${1:-"http://127.0.0.1:8000"}
FIX_MODE=0; SKIP_STRESS=0; SKIP_DDOS=0; SKIP_VULN=0
REPORT_DIR="./reports"; DURATION=30; THREADS=50

for arg in "$@"; do
    case $arg in
        --fix)           FIX_MODE=1 ;;
        --skip-stress)   SKIP_STRESS=1 ;;
        --skip-ddos)     SKIP_DDOS=1 ;;
        --skip-vuln)     SKIP_VULN=1 ;;
        --report-dir=*)  REPORT_DIR="${arg#*=}" ;;
        --duration=*)    DURATION="${arg#*=}" ;;
        --threads=*)     THREADS="${arg#*=}" ;;
    esac
done

mkdir -p "$REPORT_DIR"
TS=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/security_audit_${TS}.txt"
VULN_FILE="${REPORT_DIR}/vulnerabilities_${TS}.txt"
STRESS_FILE="${REPORT_DIR}/stress_results_${TS}.txt"
DDOS_FILE="${REPORT_DIR}/ddos_results_${TS}.txt"

FAIL_COUNT=0; WARN_COUNT=0; PASS_COUNT=0; CRITICAL_COUNT=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "$1" | tee -a "$REPORT_FILE"; }
slog() { echo -e "$1" | tee -a "$STRESS_FILE"; }
dlog() { echo -e "$1" | tee -a "$DDOS_FILE"; }

fail() { log "${RED}[FAIL]${NC} $1"; echo "[FAIL] $1" >> "$VULN_FILE"; ((FAIL_COUNT++)); }
crit() { log "${RED}${BOLD}[CRIT]${NC} $1"; echo "[CRITICAL] $1" >> "$VULN_FILE"; ((CRITICAL_COUNT++)); ((FAIL_COUNT++)); }
warn() { log "${YELLOW}[WARN]${NC} $1"; ((WARN_COUNT++)); }
pass() { log "${GREEN}[PASS]${NC} $1"; ((PASS_COUNT++)); }
info() { log "${CYAN}[INFO]${NC} $1"; }

section() {
    log ""
    log "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    log "${BOLD}${BLUE}║  $1${NC}"
    log "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
}

# ============================================================
# TOOL CHECK
# ============================================================
check_tools() {
    section "TOOL AVAILABILITY"
    for tool in curl python3; do
        command -v "$tool" &>/dev/null && pass "Required: $tool" || crit "MISSING required tool: $tool"
    done
    for tool in ab wrk siege hping3 slowhttptest nmap nikto sqlmap; do
        command -v "$tool" &>/dev/null && pass "Optional available: $tool" \
            || warn "Optional missing: $tool (sudo apt-get install apache2-utils hping3 nmap nikto sqlmap slowhttptest; wrk/siege via package manager)"
    done
}

# ============================================================
# 0. ENVIRONMENT FILE
# ============================================================
check_env_file() {
    section "0 · Environment / Secrets Configuration"
    [[ ! -f .env ]] && { warn ".env not found in current directory — run from project root"; return; }

    DEBUG_VAL=$(grep -E "^DEBUG=" .env | cut -d= -f2 | tr -d '[:space:]')
    if [[ "$DEBUG_VAL" == "True" || "$DEBUG_VAL" == "1" || -z "$DEBUG_VAL" ]]; then
        crit "DEBUG=True — exposes stack traces, SQL, SECRET_KEY, debug toolbar to any visitor.
        Fix: set DEBUG=False in .env"
        [[ $FIX_MODE -eq 1 ]] && sed -i 's/^DEBUG=True/DEBUG=False/' .env && warn "Auto-patched: DEBUG=False"
    else
        pass "DEBUG disabled"
    fi

    SK=$(grep -E "^SECRET_KEY=" .env | cut -d= -f2)
    if echo "$SK" | grep -qiE "insecure|change.me|secret|example|test|dev|placeholder"; then
        crit "SECRET_KEY is a placeholder — attackers can forge sessions & CSRF tokens.
        Fix: python3 -c \"from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())\""
        if [[ $FIX_MODE -eq 1 ]]; then
            NEW_SK=$(python3 -c "import secrets,string; print(''.join(secrets.choice(string.printable[:62]) for _ in range(64)))")
            sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${NEW_SK}|" .env && warn "Auto-patched: new SECRET_KEY written"
        fi
    else
        pass "SECRET_KEY appears non-default (${#SK} chars)"
    fi

    AH=$(grep -E "^ALLOWED_HOSTS=" .env | cut -d= -f2)
    [[ "$AH" == "*" ]] && fail "ALLOWED_HOSTS=* — Host header injection possible" || pass "ALLOWED_HOSTS: $AH"

    DB_USER=$(grep -E "^DB_USER=" .env | cut -d= -f2)
    [[ "$DB_USER" == "root" ]] \
        && fail "DB_USER=root — create a least-privilege DB user" \
        || pass "DB_USER: $DB_USER"

    DB_PASS=$(grep -E "^DB_PASSWORD=" .env | cut -d= -f2)
    [[ ${#DB_PASS} -lt 16 ]] \
        && fail "DB_PASSWORD too short (${#DB_PASS} chars) — use ≥16 random chars" \
        || pass "DB_PASSWORD length OK (${#DB_PASS} chars)"

    grep -qE "^NGROK_AUTHTOKEN=.+" .env \
        && crit "NGROK_AUTHTOKEN in .env — Ngrok bypasses firewall, must never be used in production"

    PERMS=$(stat -c "%a" .env 2>/dev/null)
    if [[ "$PERMS" != "600" && "$PERMS" != "400" ]]; then
        fail ".env permissions $PERMS — must be 600. Fix: chmod 600 .env"
        [[ $FIX_MODE -eq 1 ]] && chmod 600 .env && warn "Auto-patched: chmod 600 .env"
    else
        pass ".env permissions: $PERMS"
    fi

    git -C . ls-files --error-unmatch .env &>/dev/null 2>&1 \
        && crit ".env is tracked by git! Fix: git rm --cached .env && echo .env >> .gitignore" \
        || pass ".env not tracked by git"
}

# ============================================================
# 1. DEBUG ENDPOINTS
# ============================================================
check_debug_endpoints() {
    section "1 · Debug & Profiler Endpoint Exposure"
    for ep in "__debug__/" "debug/" "debug_toolbar/" "_profiler/" "silk/" ".env" \
               "settings.py" "django.log" "requirements.txt" "Dockerfile" \
               "docker-compose.yml" ".git/config" ".git/HEAD" "manage.py" "README.md"; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/${ep}")
        LEN=$(curl -s -m 5 "${TARGET}/${ep}" 2>/dev/null | wc -c)
        if [[ "$CODE" == "200" && "$LEN" -gt 100 ]]; then
            crit "EXPOSED: ${TARGET}/${ep} (HTTP $CODE, ${LEN}B)
            Fix: set DEBUG=False; add Nginx: location ~* \\.(env|log|py|git)$ { deny all; }"
        else
            pass "Protected: /${ep} (HTTP $CODE)"
        fi
    done
}

# ============================================================
# 2. SECURITY HEADERS
# ============================================================
check_security_headers() {
    section "2 · HTTP Security Headers"
    HEADERS=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null)

    for entry in \
        "X-Content-Type-Options:Prevents MIME-sniffing:nosniff" \
        "X-Frame-Options:Prevents clickjacking:DENY" \
        "X-XSS-Protection:Legacy XSS filter:1; mode=block" \
        "Referrer-Policy:Controls referrer leakage:same-origin" \
        "Strict-Transport-Security:Forces HTTPS:max-age=31536000; includeSubDomains" \
        "Content-Security-Policy:Prevents XSS injection:default-src 'self'" \
        "Permissions-Policy:Restricts browser features:geolocation=()"; do
        IFS=: read -r hdr desc recommended <<< "$entry"
        if echo "$HEADERS" | grep -qi "^${hdr}:"; then
            pass "Header present: $hdr"
        else
            fail "Missing header: $hdr — $desc (recommended: $recommended)"
        fi
    done

    SERVER=$(echo "$HEADERS" | grep -i "^Server:" | head -1 | tr -d '\r')
    echo "$SERVER" | grep -qiE "CPython|Django|Werkzeug|gunicorn" \
        && fail "Server header leaks stack: $SERVER — hide with Nginx server_tokens off;" \
        || pass "Server header clean: $SERVER"
}

# ============================================================
# 3. ADMIN PANEL
# ============================================================
check_admin_panel() {
    section "3 · Admin Panel Security"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/admin/")
    pass "Admin returns HTTP $CODE"
    warn "Change /admin/ to a non-guessable URL path in production."

    # Rate limiting
    for i in $(seq 1 10); do
        curl -s -o /dev/null -m 2 -X POST "${TARGET}/admin/login/" \
            -d "username=admin&password=wrong${i}" 2>/dev/null
    done
    FINAL=$(curl -s -o /dev/null -w "%{http_code}" -m 3 -X POST "${TARGET}/admin/login/" \
        -d "username=admin&password=wrongfinal" 2>/dev/null)
    if [[ "$FINAL" == "429" || "$FINAL" == "403" ]]; then
        pass "Admin login rate limiting active after 10 attempts (HTTP $FINAL)"
    else
        fail "No rate limiting on admin login after 10 attempts (HTTP $FINAL).
        Fix: pip install django-axes; set AXES_FAILURE_LIMIT=5 in settings."
    fi
}

# ============================================================
# 4. CSRF
# ============================================================
check_csrf() {
    section "4 · CSRF Protection"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 -X POST "${TARGET}/login/" \
        -d "username=test&password=test" 2>/dev/null)
    if [[ "$CODE" == "403" ]]; then
        pass "CSRF enforced — POST without token returns 403"
    elif [[ "$CODE" == "200" || "$CODE" == "302" ]]; then
        crit "CSRF may NOT be enforced — POST without CSRF token returned $CODE.
        Fix: ensure CsrfViewMiddleware is in MIDDLEWARE."
    else
        info "CSRF returned HTTP $CODE — verify manually"
    fi
}

# ============================================================
# 5. SQL INJECTION
# ============================================================
check_sql_injection() {
    section "5 · SQL Injection"
    local endpoints=("/?id=" "/?search=" "/?q=" "/?user_id=" "/?page=" "/?sort=")
    local payloads=("'" "1 OR 1=1" "' OR '1'='1" "' UNION SELECT NULL,NULL--"
                    "1; SELECT SLEEP(2)--" "admin'--" "'; DROP TABLE auth_user--")
    local errpat="syntax error|OperationalError|ProgrammingError|mysql_fetch|django\.db|ORA-|SQLite"

    FOUND=0
    for ep in "${endpoints[@]}"; do
        for pl in "${payloads[@]}"; do
            ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pl" 2>/dev/null)
            START=$(date +%s%N)
            RESP=$(curl -s -m 8 "${TARGET}${ep}${ENC}" 2>/dev/null)
            END=$(date +%s%N)
            MS=$(( (END-START)/1000000 ))
            if echo "$RESP" | grep -qiE "$errpat"; then
                crit "SQLi ERROR-BASED at ${ep} payload='${pl}'
                Fix: use ORM only; never interpolate user input into raw SQL."
                FOUND=1
            fi
            if [[ "$MS" -gt 2000 ]] && echo "$pl" | grep -qi "sleep\|waitfor"; then
                fail "SQLi TIME-BASED BLIND at ${ep} — ${MS}ms delay with SLEEP payload"
                FOUND=1
            fi
        done
    done

    if command -v sqlmap &>/dev/null; then
        info "Running sqlmap quick scan..."
        sqlmap -u "${TARGET}/?id=1" --batch --level=1 --risk=1 --timeout=10 \
            --output-dir="${REPORT_DIR}/sqlmap_${TS}" 2>/dev/null | tail -3 | tee -a "$REPORT_FILE"
    fi

    [[ $FOUND -eq 0 ]] && pass "No SQL injection indicators found"
}

# ============================================================
# 6. XSS
# ============================================================
check_xss() {
    section "6 · Cross-Site Scripting (XSS)"
    local payloads=("<script>alert(1)</script>" "<img src=x onerror=alert(1)>"
                    "'><script>alert(1)</script>" "<svg onload=alert(1)>"
                    "\"><img src=x onerror=alert(document.cookie)>" "{{7*7}}" "\${7*7}")
    local params=("q" "search" "name" "message" "comment" "title" "content" "text")

    FOUND=0
    for param in "${params[@]}"; do
        for pl in "${payloads[@]}"; do
            ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pl" 2>/dev/null)
            RESP=$(curl -s -m 5 "${TARGET}/?${param}=${ENC}" 2>/dev/null)
            if echo "$RESP" | grep -qF "$pl"; then
                fail "XSS REFLECTED at ?${param}= payload='${pl}'
                Fix: never use mark_safe() with user input; check raw HttpResponse views."
                FOUND=1
            fi
            if [[ "$pl" == "{{7*7}}" ]] && echo "$RESP" | grep -q "49"; then
                crit "SERVER-SIDE TEMPLATE INJECTION — {{7*7}} evaluated to 49!
                Fix: never pass user input to Template() or render_to_string() directly."
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No reflected XSS found"
}

# ============================================================
# 7. PATH TRAVERSAL
# ============================================================
check_path_traversal() {
    section "7 · Path Traversal"
    local payloads=("../../../../etc/passwd" "....//....//etc/passwd"
                    "%2e%2e%2f%2e%2e%2fetc%2fpasswd" "..%252f..%252fetc%252fpasswd"
                    "..%c0%af..%c0%afetc%c0%afpasswd" "..;/..;/etc/passwd")
    local params=("file" "path" "name" "template" "doc" "download" "img" "page" "view")

    FOUND=0
    for param in "${params[@]}"; do
        for pl in "${payloads[@]}"; do
            ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pl" 2>/dev/null)
            RESP=$(curl -s -m 5 "${TARGET}/?${param}=${ENC}" 2>/dev/null)
            if echo "$RESP" | grep -qE "root:(x|!|\*):0:0|/bin/bash|/sbin/nologin"; then
                crit "PATH TRAVERSAL at ?${param}= — /etc/passwd readable!
                Fix: validate paths with os.path.abspath(); check prefix against ALLOWED_DIRS."
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No path traversal indicators found"
}

# ============================================================
# 8. OPEN REDIRECT
# ============================================================
check_open_redirect() {
    section "8 · Open Redirect"
    local payloads=("//evil.com" "https://evil.com" "//evil.com/%2F.." "/\\\\evil.com" "/%2F%2Fevil.com")
    local params=("next" "redirect" "url" "return" "goto" "callback" "dest" "target")

    FOUND=0
    for param in "${params[@]}"; do
        for pl in "${payloads[@]}"; do
            ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pl" 2>/dev/null)
            LOC=$(curl -s -I -m 5 "${TARGET}/login/?${param}=${ENC}" 2>/dev/null \
                | grep -i "^Location:" | tail -1 | tr -d '\r' | cut -d' ' -f2-)
            if echo "$LOC" | grep -qi "evil\.com"; then
                fail "OPEN REDIRECT ?${param}=${pl} → $LOC
                Fix: use url_has_allowed_host_and_scheme() before redirect."
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No open redirect detected"
}

# ============================================================
# 9. COMMAND INJECTION
# ============================================================
check_command_injection() {
    section "9 · Command Injection"
    local payloads=("; id" "| id" "\$(id)" "\`id\`" "; cat /etc/passwd" "|| id" "&& id")
    local params=("ip" "host" "cmd" "ping" "url" "exec" "command" "shell")

    FOUND=0
    for param in "${params[@]}"; do
        for pl in "${payloads[@]}"; do
            ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pl" 2>/dev/null)
            RESP=$(curl -s -m 8 "${TARGET}/?${param}=${ENC}" 2>/dev/null)
            if echo "$RESP" | grep -qE "uid=[0-9]+\([a-z]+\)|root:|/bin/bash"; then
                crit "COMMAND INJECTION at ?${param}= payload='${pl}'
                Fix: never pass user input to subprocess/os.system."
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No command injection indicators found"
}

# ============================================================
# 10. SSRF
# ============================================================
check_ssrf() {
    section "10 · SSRF (Server-Side Request Forgery)"
    local payloads=("http://169.254.169.254/latest/meta-data/"
                    "http://127.0.0.1:8000/" "http://localhost/" "file:///etc/passwd"
                    "http://metadata.google.internal/" "http://100.100.100.200/latest/meta-data/")
    local params=("url" "link" "src" "image" "webhook" "callback" "endpoint" "api")

    FOUND=0
    for param in "${params[@]}"; do
        for pl in "${payloads[@]}"; do
            ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pl" 2>/dev/null)
            RESP=$(curl -s -m 5 "${TARGET}/?${param}=${ENC}" 2>/dev/null)
            if echo "$RESP" | grep -qiE "ami-id|instance-id|metadata|local-hostname|root:x:"; then
                crit "SSRF at ?${param}= — internal metadata/services reachable!
                Fix: validate URLs with allowlist; block private IP ranges (RFC1918)."
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No SSRF indicators found"
}

# ============================================================
# 11. IDOR
# ============================================================
check_idor() {
    section "11 · IDOR (Insecure Direct Object Reference)"
    for ep in "/api/users/1/" "/api/users/2/" "/api/profile/1/" \
              "/export/student/1/" "/media/notifications/1.pdf"; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}${ep}")
        BODY=$(curl -s -m 5 "${TARGET}${ep}" 2>/dev/null)
        if [[ "$CODE" == "200" ]] && echo "$BODY" | grep -qiE "email|username|password|phone"; then
            fail "IDOR: ${ep} returns user data unauthenticated.
            Fix: filter querysets by request.user; verify ownership in every view."
        elif [[ "$CODE" =~ ^(401|403|302)$ ]]; then
            pass "IDOR protected: ${ep} (HTTP $CODE)"
        else
            info "IDOR: ${ep} returned HTTP $CODE"
        fi
    done
}

# ============================================================
# 12. XXE
# ============================================================
check_xxe() {
    section "12 · XXE (XML External Entity Injection)"
    XXE_PL='<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><root>&xxe;</root>'
    FOUND=0
    for ep in "/api/" "/import/" "/upload/" "/xml/" "/data/"; do
        RESP=$(curl -s -m 5 -X POST "${TARGET}${ep}" \
            -H "Content-Type: application/xml" -d "$XXE_PL" 2>/dev/null)
        if echo "$RESP" | grep -qE "root:(x|!|\*):0:0|/bin/bash"; then
            crit "XXE at ${ep} — /etc/passwd read via XML entity!
            Fix: disable external entity processing in your XML parser."
            FOUND=1
        fi
    done
    [[ $FOUND -eq 0 ]] && pass "No XXE indicators found"
}

# ============================================================
# 13. AUTH & SESSION
# ============================================================
check_auth_session() {
    section "13 · Authentication & Session Security"

    # Session fixation
    SID_BEFORE=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null | grep -i "sessionid" | grep -oP "sessionid=[^;]+" | head -1)
    curl -s -o /dev/null -m 5 -X POST "${TARGET}/login/" -d "username=x&password=x" -b "$SID_BEFORE" 2>/dev/null
    SID_AFTER=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null | grep -i "sessionid" | grep -oP "sessionid=[^;]+" | head -1)
    if [[ "$SID_BEFORE" == "$SID_AFTER" && -n "$SID_BEFORE" ]]; then
        fail "Potential SESSION FIXATION — session ID unchanged after login.
        Fix: call request.session.cycle_key() on successful login."
    else
        pass "Session ID rotates (no fixation detected)"
    fi

    # Password reset page
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/password-reset/" 2>/dev/null)
    [[ "$CODE" == "200" ]] && pass "Password reset endpoint accessible" \
        && warn "Verify reset tokens expire after first use and within 24h."

    # GET logout
    LCODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 -X GET "${TARGET}/logout/" 2>/dev/null)
    [[ "$LCODE" == "200" || "$LCODE" == "302" ]] \
        && warn "Logout may be accessible via GET — use POST+CSRF to prevent CSRF-based logout."
}

# ============================================================
# 14. COOKIE SECURITY
# ============================================================
check_cookie_security() {
    section "14 · Cookie Security Flags"
    COOKIE_HEADERS=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null | grep -i "Set-Cookie")
    if [[ -z "$COOKIE_HEADERS" ]]; then
        info "No Set-Cookie on home page (cookies set after login)"
        return
    fi
    while IFS= read -r cookie; do
        [[ -z "$cookie" ]] && continue
        NAME=$(echo "$cookie" | grep -oP "Set-Cookie:\s*\K[^=]+" | tr -d ' ')
        echo "$cookie" | grep -qi "HttpOnly" && pass "HttpOnly OK: $NAME" || fail "Missing HttpOnly: $NAME"
        echo "$cookie" | grep -qi "SameSite"  || warn "Missing SameSite: $NAME"
        echo "$TARGET" | grep -q "^https://" && ! echo "$cookie" | grep -qi "Secure" \
            && fail "Missing Secure flag on HTTPS cookie: $NAME"
    done <<< "$COOKIE_HEADERS"
}

# ============================================================
# 15. SENSITIVE FILES
# ============================================================
check_sensitive_files() {
    section "15 · Sensitive File & Media Exposure"
    for path in ".env" ".env.example" "settings.py" "django.log" "manage.py" \
                "requirements.txt" "docker-compose.yml" "Dockerfile" ".git/config" \
                "README.md" "DEVELOPER_DOCS.md" "media/notifications/" \
                "media/timetable_logos/" "feasibility_reports/"; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/${path}")
        LEN=$(curl -s -m 5 "${TARGET}/${path}" 2>/dev/null | wc -c)
        if [[ "$CODE" == "200" && "$LEN" -gt 50 ]]; then
            fail "EXPOSED: /${path} (${LEN}B)
            Fix: Nginx deny rules; never serve project root via MEDIA_ROOT."
        else
            pass "Protected: /${path} (HTTP $CODE)"
        fi
    done
    for dir in "media/" "static/" "media/notifications/"; do
        BODY=$(curl -s -m 5 "${TARGET}/${dir}" 2>/dev/null)
        echo "$BODY" | grep -qi "Index of\|Directory listing\|Parent Directory" \
            && fail "Directory listing enabled: /${dir} — add 'autoindex off;' in Nginx."
    done
}

# ============================================================
# 16. INFORMATION DISCLOSURE
# ============================================================
check_info_disclosure() {
    section "16 · Information Disclosure"

    RESP_404=$(curl -s -m 5 "${TARGET}/no-such-page-xyzqv987/" 2>/dev/null)
    echo "$RESP_404" | grep -qi "You're seeing this error because you have DEBUG" \
        && crit "Django debug 404 reveals ALL URL patterns — set DEBUG=False." \
        || pass "Custom 404 returned (debug 404 inactive)"

    RESP_ERR=$(curl -s -m 5 "${TARGET}/trigger-error-99xyz/" 2>/dev/null)
    echo "$RESP_ERR" | grep -qE "Traceback|File \"/|site-packages" \
        && crit "Stack trace visible in error response — set DEBUG=False; configure ADMINS." \
        || pass "No stack trace in error responses"

    HOME=$(curl -s -m 5 "${TARGET}/" 2>/dev/null)
    EMAILS=$(echo "$HOME" | grep -oE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" | sort -u)
    [[ -n "$EMAILS" ]] \
        && warn "Emails in page source (scraped by exploit): $EMAILS — use contact form or obfuscate." \
        || pass "No plaintext emails in home page source"

    HDRS=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null)
    echo "$HDRS" | grep -qiE "X-Powered-By:|X-Django-Version:" \
        && fail "Version info disclosed in response headers."
}

# ============================================================
# 17. TLS
# ============================================================
check_tls() {
    section "17 · TLS / HTTPS"
    if echo "$TARGET" | grep -q "^https://"; then
        HSTS=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null | grep -i "Strict-Transport-Security")
        [[ -n "$HSTS" ]] && pass "HSTS: $HSTS" || fail "HSTS header missing."
        HTTP_TARGET=$(echo "$TARGET" | sed 's/^https/http/')
        RC=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "$HTTP_TARGET" 2>/dev/null)
        [[ "$RC" =~ ^(301|302)$ ]] && pass "HTTP→HTTPS redirect (HTTP $RC)" \
            || fail "HTTP does not redirect to HTTPS (HTTP $RC)."
    else
        warn "Target is HTTP — in production terminate TLS at Nginx.
        Set SECURE_SSL_REDIRECT=True, SESSION_COOKIE_SECURE=True, CSRF_COOKIE_SECURE=True."
    fi
}

# ============================================================
# 18. API AUTHENTICATION
# ============================================================
check_api_auth() {
    section "18 · API Endpoint Authentication"
    for ep in "api/" "api/v1/" "api/users/" "api/flag/" "api/export/" "api/timetable/"; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/${ep}")
        BODY=$(curl -s -m 5 "${TARGET}/${ep}" 2>/dev/null)
        if [[ "$CODE" == "200" ]] && echo "$BODY" | grep -qiE '"[a-z]+":|user|email|data|result'; then
            fail "API /${ep} returns data without auth (HTTP $CODE).
            Fix: add @login_required or IsAuthenticated to all API views."
        elif [[ "$CODE" =~ ^(401|403|302)$ ]]; then
            pass "API /${ep} requires auth (HTTP $CODE)"
        else
            info "API /${ep}: HTTP $CODE"
        fi
    done
}

# ============================================================
# 19. NIKTO
# ============================================================
check_nikto() {
    section "19 · Nikto Web Vulnerability Scan"
    if ! command -v nikto &>/dev/null; then
        warn "nikto not installed — sudo apt-get install nikto"
        return
    fi
    NIKTO_OUT="${REPORT_DIR}/nikto_${TS}.txt"
    info "Running nikto (2–5 min)..."
    nikto -h "$TARGET" -output "$NIKTO_OUT" -Format txt -Tuning 1234579 2>/dev/null
    VULNS=$(grep -c "OSVDB\|+ " "$NIKTO_OUT" 2>/dev/null || echo 0)
    [[ "$VULNS" -gt 0 ]] && fail "Nikto found $VULNS issue(s) — see $NIKTO_OUT" \
        || pass "Nikto scan clean — $NIKTO_OUT"
}

# ============================================================
# 20. PORT SCAN
# ============================================================
check_ports() {
    section "20 · Open Port Scan"
    if ! command -v nmap &>/dev/null; then
        warn "nmap not installed — sudo apt-get install nmap"
        return
    fi
    HOST=$(echo "$TARGET" | sed 's|https\?://||' | cut -d/ -f1 | cut -d: -f1)
    NMAP_OUT=$(nmap -sV --open -F "$HOST" 2>/dev/null)
    echo "$NMAP_OUT" >> "$REPORT_FILE"
    UNEX=$(echo "$NMAP_OUT" | grep "open" | grep -vE "80/tcp|443/tcp|22/tcp")
    [[ -n "$UNEX" ]] \
        && warn "Unexpected open ports:
$UNEX
        Close unnecessary ports in firewall/security groups." \
        || pass "No unexpected open ports"
}

# ============================================================
# ████  STRESS TESTING  ████
# ============================================================
run_stress_tests() {
    [[ $SKIP_STRESS -eq 1 ]] && { info "Stress tests skipped (--skip-stress)"; return; }
    section "STRESS TESTING"
    slog "Target: $TARGET | Threads: $THREADS | Duration: ${DURATION}s | $(date)"

    # 21. BASELINE LOAD (Apache Bench)
    if command -v ab &>/dev/null; then
        slog "\n${MAGENTA}[STRESS-21] Baseline Load — Apache Bench${NC}"
        AB_OUT=$(ab -n $(( THREADS * DURATION )) -c "$THREADS" -t "$DURATION" \
            -H "Accept-Encoding: gzip,deflate" "${TARGET}/" 2>&1)
        echo "$AB_OUT" >> "$STRESS_FILE"
        RPS=$(echo "$AB_OUT" | grep "Requests per second" | awk '{print $4}')
        P99=$(echo "$AB_OUT" | grep "99%" | awk '{print $2}')
        FAILED=$(echo "$AB_OUT" | grep "Failed requests" | awk '{print $3}')
        slog "  RPS=$RPS | P99=${P99}ms | Failed=$FAILED"
        log  "  [STRESS-21] RPS=$RPS | P99=${P99}ms | Failed=$FAILED"
        RPS_INT=${RPS%.*}
        if [[ -n "$RPS_INT" ]]; then
            [[ "$RPS_INT" -lt 10 ]] && fail "LOW throughput: ${RPS} RPS under $THREADS users." \
            || [[ "$RPS_INT" -lt 50 ]] && warn "MODERATE throughput: ${RPS} RPS — add Redis cache & DB indexes." \
            || pass "Baseline load OK: ${RPS} RPS, P99 ${P99}ms"
        fi
        [[ -n "$FAILED" && "$FAILED" -gt 0 ]] && fail "Apache Bench: $FAILED failed requests under load."
    else
        warn "ab not available — install apache2-utils for baseline load test"
    fi

    # 22. SPIKE TEST
    slog "\n${MAGENTA}[STRESS-22] Spike Test — $(( THREADS*2 )) simultaneous users${NC}"
    SPIKE=$(( THREADS * 2 ))
    for i in $(seq 1 "$SPIKE"); do
        curl -s -o /dev/null -w "%{http_code}\n" -m 5 "${TARGET}/" &
    done
    SPIKE_RESULTS=$(wait && echo done)
    CODE_AFTER=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/" 2>/dev/null)
    [[ "$CODE_AFTER" == "200" || "$CODE_AFTER" == "302" ]] \
        && pass "Spike test: server responsive after $SPIKE simultaneous requests (HTTP $CODE_AFTER)" \
        || fail "Spike test: server unresponsive after $SPIKE simultaneous requests (HTTP $CODE_AFTER)"

    # 23. SOAK TEST
    slog "\n${MAGENTA}[STRESS-23] Soak Test — sustained load for ${DURATION}s${NC}"
    SOAK_ERR=0; SOAK_TOTAL=0
    SOAK_END=$(( $(date +%s) + DURATION ))
    while [[ $(date +%s) -lt $SOAK_END ]]; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "${TARGET}/" 2>/dev/null)
        ((SOAK_TOTAL++))
        [[ "$CODE" != "200" && "$CODE" != "302" && "$CODE" != "301" ]] && ((SOAK_ERR++))
        sleep 0.5
    done
    PCT=$(( SOAK_ERR * 100 / (SOAK_TOTAL > 0 ? SOAK_TOTAL : 1) ))
    slog "  Soak: $SOAK_TOTAL requests, $SOAK_ERR errors ($PCT%)"
    log  "  [STRESS-23] Soak $SOAK_TOTAL reqs, $SOAK_ERR errors ($PCT%)"
    [[ "$PCT" -gt 5 ]] \
        && fail "Soak: ${PCT}% error rate over ${DURATION}s — system unstable under sustained load." \
        || pass "Soak: ${PCT}% error rate over ${DURATION}s (OK)"

    # 24. WRK BENCHMARK
    if command -v wrk &>/dev/null; then
        slog "\n${MAGENTA}[STRESS-24] wrk HTTP Benchmark${NC}"
        WRK=$(wrk -t"$THREADS" -c"$THREADS" -d"${DURATION}s" --timeout 5s "${TARGET}/" 2>&1)
        echo "$WRK" >> "$STRESS_FILE"
        slog "$WRK"
        pass "wrk benchmark complete — see $STRESS_FILE"
    fi

    # 25. SIEGE
    if command -v siege &>/dev/null; then
        slog "\n${MAGENTA}[STRESS-25] Siege Stress Test${NC}"
        SIEGE=$(siege -c"$THREADS" -t"${DURATION}S" -b "${TARGET}/" 2>&1)
        echo "$SIEGE" >> "$STRESS_FILE"
        slog "$SIEGE"
        pass "Siege complete — see $STRESS_FILE"
    fi

    # 26. LARGE PAYLOAD
    slog "\n${MAGENTA}[STRESS-26] Large Payload Test (100KB POST)${NC}"
    BIG=$(python3 -c "print('A'*100000)")
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 -X POST "${TARGET}/login/" \
        -d "username=${BIG}&password=test" 2>/dev/null)
    [[ "$CODE" == "413" || "$CODE" == "400" || "$CODE" == "403" ]] \
        && pass "Server rejects oversized payload (HTTP $CODE)" \
        || warn "Server accepted 100KB payload (HTTP $CODE) — set client_max_body_size in Nginx."

    # 27. RESPONSE STABILITY / MEMORY PROBE
    slog "\n${MAGENTA}[STRESS-27] Response Stability Probe (10 sequential requests)${NC}"
    JAR="/tmp/stability_cookies_$$.txt"
    curl -s -c "$JAR" "${TARGET}/" > /dev/null 2>&1
    SIZES=(); for i in $(seq 1 10); do
        S=$(curl -s -b "$JAR" -o /dev/null -w "%{size_download}" -m 5 "${TARGET}/" 2>/dev/null)
        SIZES+=("$S"); sleep 1
    done
    rm -f "$JAR"
    MAX=${SIZES[0]}; MIN=${SIZES[0]}
    for s in "${SIZES[@]}"; do (( s > MAX )) && MAX=$s; (( s < MIN )) && MIN=$s; done
    VAR=$(( MAX - MIN ))
    slog "  Size variance: ${VAR}B (min=$MIN max=$MAX)"
    [[ "$VAR" -gt 50000 ]] \
        && warn "High response variance (${VAR}B) — possible memory/content leak." \
        || pass "Response size stable (variance: ${VAR}B)"
}

# ============================================================
# ████  DDoS SIMULATION  ████
# ============================================================
run_ddos_tests() {
    [[ $SKIP_DDOS -eq 1 ]] && { info "DDoS simulation skipped (--skip-ddos)"; return; }
    section "DDoS SIMULATION & RESILIENCE"
    dlog "Target: $TARGET | Duration: ${DURATION}s | Threads: $THREADS | $(date)"
    dlog "⚠  Run only against infrastructure you own and have permission to test."

    HOST=$(echo "$TARGET" | sed 's|https\?://||' | cut -d/ -f1 | cut -d: -f1)
    PORT=$(echo "$TARGET" | grep -oP ":\d+$" | tr -d ':')
    [[ -z "$PORT" ]] && { echo "$TARGET" | grep -q "^https" && PORT=443 || PORT=80; }

    # 28. HTTP FLOOD
    dlog "\n${RED}[DDOS-28] HTTP Flood — $THREADS workers for ${DURATION}s${NC}"
    FLOOD_END=$(( $(date +%s) + DURATION ))
    FLOOD_TMP="/tmp/flood_$$.txt"
    flood_worker() {
        while [[ $(date +%s) -lt $FLOOD_END ]]; do
            CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 2 \
                -H "Cache-Control: no-cache" \
                -H "X-Forwarded-For: $((RANDOM%254+1)).$((RANDOM%254+1)).$((RANDOM%254+1)).$((RANDOM%254+1))" \
                "${TARGET}/?_=${RANDOM}" 2>/dev/null)
            echo "$CODE"
        done
    }
    export -f flood_worker
    export FLOOD_END TARGET
    for i in $(seq 1 "$THREADS"); do flood_worker >> "$FLOOD_TMP" & done
    wait
    OK=$(grep -cE "^(200|302|301)$" "$FLOOD_TMP" 2>/dev/null || echo 0)
    R429=$(grep -c "^429$" "$FLOOD_TMP" 2>/dev/null || echo 0)
    ERR=$(grep -cE "^(500|502|503|504)$" "$FLOOD_TMP" 2>/dev/null || echo 0)
    TOTAL=$(wc -l < "$FLOOD_TMP")
    rm -f "$FLOOD_TMP"
    dlog "  HTTP Flood: total=$TOTAL ok=$OK rate_limited=$R429 errors=$ERR"
    log  "  [DDOS-28] HTTP Flood: total=$TOTAL ok=$OK rate_limited=$R429 errors=$ERR"
    [[ "$R429" -gt 0 ]] && pass "Rate limiting active during HTTP flood ($R429 blocked)" \
        || fail "No rate limiting during ${THREADS}-thread HTTP flood.
        Fix: Nginx limit_req_zone / limit_conn_zone; Cloudflare WAF."
    [[ "$TOTAL" -gt 0 && "$ERR" -gt $(( TOTAL / 5 )) ]] \
        && fail "HTTP flood caused >20% server errors ($ERR/$TOTAL) — server overwhelmed."

    # 29. CACHE-BUSTING FLOOD
    dlog "\n${RED}[DDOS-29] Cache-Busting Flood — unique URLs${NC}"
    for i in $(seq 1 60); do
        curl -s -o /dev/null -w "%{http_code}\n" -m 2 \
            "${TARGET}/?nocache=${RANDOM}${RANDOM}" &
    done; wait
    CODE_AFTER=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/" 2>/dev/null)
    [[ "$CODE_AFTER" == "200" || "$CODE_AFTER" == "302" ]] \
        && pass "Server responsive after cache-busting flood (HTTP $CODE_AFTER)" \
        || fail "Server unresponsive after cache-busting flood (HTTP $CODE_AFTER)."

    # 30. SLOWLORIS
    dlog "\n${RED}[DDOS-30] Slowloris Connection Exhaustion${NC}"
    if command -v slowhttptest &>/dev/null; then
        SL_OUT="${REPORT_DIR}/slowloris_${TS}.html"
        slowhttptest -c 200 -H -i 10 -r 200 -t GET -u "${TARGET}/" -x 24 -p 3 -o "$SL_OUT" 2>/dev/null
        CODE_SL=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "${TARGET}/" 2>/dev/null)
        [[ "$CODE_SL" == "200" || "$CODE_SL" == "302" ]] \
            && pass "Server survived slowhttptest Slowloris — $SL_OUT" \
            || fail "Server DOWN after Slowloris (HTTP $CODE_SL).
            Fix: client_header_timeout 10s; client_body_timeout 10s; in Nginx."
    else
        dlog "  slowhttptest not installed — running Python Slowloris simulation..."
        python3 <<PYSLOWLORIS &
import socket, time, threading

host = "${HOST}"
port = ${PORT}
socks = []
for _ in range(100):
    try:
        s = socket.socket(); s.settimeout(4); s.connect((host, port))
        s.send(f"GET /?{id(s)} HTTP/1.1\r\nHost: {host}\r\n".encode())
        socks.append(s)
    except: pass

time.sleep(12)
alive = sum(1 for s in socks if (lambda: (s.send(b"X-a: b\r\n"), True) or False)() is True)
print(f"Slowloris: {len(socks)} connections held for 12s")
for s in socks:
    try: s.close()
    except: pass
PYSLOWLORIS
        SL_PID=$!; sleep 15; kill $SL_PID 2>/dev/null; wait $SL_PID 2>/dev/null
        CODE_SL=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "${TARGET}/" 2>/dev/null)
        [[ "$CODE_SL" == "200" || "$CODE_SL" == "302" ]] \
            && pass "Server alive after Slowloris simulation (HTTP $CODE_SL)" \
            || fail "Server DOWN after Slowloris (HTTP $CODE_SL).
            Fix: client_header_timeout 10s; client_body_timeout 10s; keepalive_timeout 15s;"
    fi

    # 31. POST BODY FLOOD
    dlog "\n${RED}[DDOS-31] POST Body Flood (30 x 10KB POSTs)${NC}"
    BIG=$(python3 -c "print('x'*10000)")
    for i in $(seq 1 30); do
        curl -s -o /dev/null -m 3 -X POST "${TARGET}/login/" \
            -d "username=${BIG}&password=${BIG}" &
    done; wait
    CODE_POST=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/" 2>/dev/null)
    [[ "$CODE_POST" == "200" || "$CODE_POST" == "302" ]] \
        && pass "Server responsive after POST flood (HTTP $CODE_POST)" \
        || fail "Server unresponsive after POST flood (HTTP $CODE_POST)."

    # 32. SYN FLOOD / TCP FLOOD
    dlog "\n${RED}[DDOS-32] SYN / TCP Connection Flood${NC}"
    if command -v hping3 &>/dev/null && [[ $EUID -eq 0 ]]; then
        dlog "  hping3 SYN flood for 10s (root mode)..."
        timeout 10 hping3 --syn --flood --rand-source -p "$PORT" "$HOST" > /dev/null 2>&1
        sleep 3
    else
        [[ $EUID -ne 0 ]] && dlog "  hping3 requires root — using Python TCP flood instead..."
        python3 <<PYTCPFLOOD &
import socket, threading, time
host, port = "${HOST}", ${PORT}
done = [False]
def conn():
    try:
        s = socket.socket(); s.settimeout(3); s.connect((host, port)); time.sleep(8); s.close()
    except: pass
ts = [threading.Thread(target=conn) for _ in range(150)]
for t in ts: t.start()
for t in ts: t.join(timeout=12)
PYTCPFLOOD
        TCP_PID=$!; sleep 15; kill $TCP_PID 2>/dev/null; wait $TCP_PID 2>/dev/null
    fi
    CODE_SYN=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "${TARGET}/" 2>/dev/null)
    [[ "$CODE_SYN" == "200" || "$CODE_SYN" == "302" ]] \
        && pass "Server recovered after TCP/SYN flood (HTTP $CODE_SYN)" \
        || fail "Server DOWN after TCP/SYN flood (HTTP $CODE_SYN).
        Fix: sysctl -w net.ipv4.tcp_syncookies=1; net.ipv4.tcp_max_syn_backlog=2048"

    # 33. HTTP/2 RAPID RESET (CVE-2023-44487)
    dlog "\n${RED}[DDOS-33] HTTP/2 Rapid Reset Simulation (CVE-2023-44487)${NC}"
    python3 <<PYRAPID &
import urllib.request, threading, time
target = "${TARGET}"
ok = 0; err = 0
def req():
    global ok, err
    try:
        urllib.request.urlopen(urllib.request.Request(target,
            headers={"Cache-Control":"no-cache"}), timeout=2)
        ok += 1
    except: err += 1
ts = [threading.Thread(target=req) for _ in range(200)]
for t in ts: t.start()
for t in ts: t.join(timeout=6)
print(f"HTTP/2 rapid: ok={ok} err={err}")
PYRAPID
    H2_PID=$!; sleep 8; kill $H2_PID 2>/dev/null; wait $H2_PID 2>/dev/null
    CODE_H2=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/" 2>/dev/null)
    [[ "$CODE_H2" == "200" || "$CODE_H2" == "302" ]] \
        && pass "Server alive after HTTP/2 rapid reset simulation (HTTP $CODE_H2)" \
        || fail "Server unresponsive after rapid reset (HTTP $CODE_H2).
        Fix: Nginx ≥1.25.3; configure http2_max_concurrent_streams."

    # 34. BRUTE FORCE / CREDENTIAL STUFFING
    dlog "\n${RED}[DDOS-34] Brute Force / Credential Stuffing (25 attempts)${NC}"
    BF_BLOCKED=0; BF_TOTAL=0
    for i in $(seq 1 25); do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 -X POST "${TARGET}/login/" \
            -d "username=admin&password=wrongpass${i}" 2>/dev/null)
        ((BF_TOTAL++))
        if [[ "$CODE" == "429" || "$CODE" == "403" ]]; then BF_BLOCKED=1; break; fi
    done
    [[ "$BF_BLOCKED" -eq 1 ]] \
        && pass "Brute force protection active — blocked within $BF_TOTAL attempts" \
        || fail "No brute force protection after 25 login attempts.
        Fix: pip install django-axes; AXES_FAILURE_LIMIT=5, AXES_COOLOFF_TIME=1"

    # 35. BANDWIDTH / LARGE RESPONSE PROBE
    dlog "\n${RED}[DDOS-35] Bandwidth Exhaustion Probe${NC}"
    for ep in "/export/global/regular-timetable/" "/export/global/exam-timetable/" "/api/"; do
        SIZE=$(curl -s -o /dev/null -w "%{size_download}" -m 10 "${TARGET}${ep}" 2>/dev/null)
        if [[ "$SIZE" -gt 5000000 ]]; then
            warn "Large unauthenticated download at ${ep}: ${SIZE}B
            Fix: require auth; paginate results; add rate limiting on export endpoints."
        elif [[ "$SIZE" -gt 0 ]]; then
            pass "${ep}: ${SIZE}B response (OK)"
        fi
    done

    # FINAL AVAILABILITY
    dlog "\n${GREEN}[DDOS-FINAL] Post-simulation availability check${NC}"
    AVAIL=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "${TARGET}/" 2>/dev/null)
    [[ "$AVAIL" == "200" || "$AVAIL" == "302" ]] \
        && pass "Server UP after all DDoS simulations (HTTP $AVAIL)" \
        || crit "Server DOWN after DDoS simulations (HTTP $AVAIL) — CRITICAL availability failure!"
}

# ============================================================
# SUMMARY
# ============================================================
print_summary() {
    section "FINAL SECURITY AUDIT SUMMARY"
    TOTAL=$(( FAIL_COUNT + WARN_COUNT + PASS_COUNT ))
    log "  ${BOLD}Target      :${NC} $TARGET"
    log "  ${BOLD}Date        :${NC} $(date)"
    log "  ${BOLD}Total checks:${NC} $TOTAL"
    log ""
    log "  ${GREEN}Passed       : $PASS_COUNT${NC}"
    log "  ${YELLOW}Warnings     : $WARN_COUNT${NC}"
    log "  ${RED}Failures     : $FAIL_COUNT${NC}"
    log "  ${RED}${BOLD}Critical     : $CRITICAL_COUNT${NC}"
    log ""
    log "  ${BOLD}Reports:${NC}"
    log "    Security audit : $REPORT_FILE"
    log "    Vulnerabilities: $VULN_FILE"
    [[ $SKIP_STRESS -eq 0 ]] && log "    Stress results : $STRESS_FILE"
    [[ $SKIP_DDOS   -eq 0 ]] && log "    DDoS results   : $DDOS_FILE"
    log ""
    if [[ $CRITICAL_COUNT -gt 0 ]]; then
        log "${RED}${BOLD}  ✗ DO NOT DEPLOY — $CRITICAL_COUNT critical issue(s) found.${NC}"; exit 2
    elif [[ $FAIL_COUNT -gt 0 ]]; then
        log "${RED}${BOLD}  ✗ DO NOT DEPLOY — $FAIL_COUNT issue(s) must be fixed.${NC}"; exit 1
    elif [[ $WARN_COUNT -gt 0 ]]; then
        log "${YELLOW}${BOLD}  ⚠  $WARN_COUNT warning(s) — review before deploying.${NC}"; exit 0
    else
        log "${GREEN}${BOLD}  ✓ All checks passed — ready for production.${NC}"; exit 0
    fi
}

# ============================================================
# ENTRY POINT
# ============================================================
log "${BOLD}${BLUE}"
log "╔══════════════════════════════════════════════════════════════╗"
log "║   University Timetable System — Full Security Audit Suite    ║"
log "╚══════════════════════════════════════════════════════════════╝"
log "${NC}"
log "  Target   : $TARGET"
log "  Fix mode : $([[ $FIX_MODE -eq 1 ]] && echo ON || echo OFF)"
log "  Stress   : $([[ $SKIP_STRESS -eq 1 ]] && echo SKIPPED || echo "ON (${DURATION}s, ${THREADS} threads)")"
log "  DDoS sim : $([[ $SKIP_DDOS -eq 1 ]] && echo SKIPPED || echo "ON (${DURATION}s, ${THREADS} threads)")"
log "  Started  : $(date)"
log ""

check_tools

if [[ $SKIP_VULN -eq 0 ]]; then
    check_env_file
    check_debug_endpoints
    check_security_headers
    check_admin_panel
    check_csrf
    check_sql_injection
    check_xss
    check_path_traversal
    check_open_redirect
    check_command_injection
    check_ssrf
    check_idor
    check_xxe
    check_auth_session
    check_cookie_security
    check_sensitive_files
    check_info_disclosure
    check_tls
    check_api_auth
    check_nikto
    check_ports
fi

run_stress_tests
run_ddos_tests
print_summary
