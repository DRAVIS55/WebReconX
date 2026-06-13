#!/bin/bash


TARGET=${1:-"http://127.0.0.1:8000"}
FIX_MODE=0
[[ "$2" == "--fix" || "$1" == "--fix" ]] && FIX_MODE=1

# ---- colours ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${CYAN}[INFO]${NC}"

REPORT_FILE="security_audit_$(date +%Y%m%d_%H%M%S).txt"
FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0

log() { echo -e "$1" | tee -a "$REPORT_FILE"; }
fail() { log "${FAIL} $1"; ((FAIL_COUNT++)); }
warn() { log "${WARN} $1"; ((WARN_COUNT++)); }
pass() { log "${PASS} $1"; ((PASS_COUNT++)); }
info() { log "${INFO} $1"; }
section() { log "\n${BOLD}${BLUE}════════════════════════════════════════${NC}"; log "${BOLD}  $1${NC}"; log "${BOLD}${BLUE}════════════════════════════════════════${NC}"; }

# ============================================================
# 0. ENVIRONMENT FILE CHECKS
# ============================================================
check_env_file() {
    section "0 · Environment / Secrets Configuration"

    # --- DEBUG must be False in production ---
    DEBUG_VAL=$(grep -E "^DEBUG=" .env 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    if [[ "$DEBUG_VAL" == "True" || "$DEBUG_VAL" == "1" || -z "$DEBUG_VAL" ]]; then
        fail "DEBUG=True is set in .env — NEVER run in production with DEBUG on.
        Risk: Full Django debug pages expose stack traces, SQL queries, local settings,
        and SECRET_KEY to any visitor. The exploit found live debug toolbar pages
        (__debug__/, debug/, silk/, _profiler/) because DEBUG was enabled."
        if [[ $FIX_MODE -eq 1 ]]; then
            sed -i 's/^DEBUG=True/DEBUG=False/' .env && warn "Auto-patched: DEBUG=False in .env"
        fi
    else
        pass "DEBUG is disabled"
    fi

    # --- Insecure SECRET_KEY ---
    SK=$(grep -E "^SECRET_KEY=" .env 2>/dev/null | cut -d= -f2)
    if echo "$SK" | grep -qi "insecure\|change-me\|secret\|example\|test\|dev"; then
        fail "SECRET_KEY looks like a placeholder/insecure default.
        Risk: A known SECRET_KEY lets attackers forge session cookies, CSRF tokens,
        and signed URL tokens, achieving full account takeover."
        if [[ $FIX_MODE -eq 1 ]]; then
            NEW_SK=$(python3 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits+'!@#\$%^&*') for _ in range(64)))")
            sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${NEW_SK}|" .env && warn "Auto-patched: new SECRET_KEY generated"
        fi
    else
        pass "SECRET_KEY appears non-default"
    fi

    # --- ALLOWED_HOSTS wildcard ---
    AH=$(grep -E "^ALLOWED_HOSTS=" .env 2>/dev/null | cut -d= -f2)
    if [[ "$AH" == "*" ]]; then
        fail "ALLOWED_HOSTS=* allows Host-header injection attacks."
    else
        pass "ALLOWED_HOSTS is not wildcard: $AH"
    fi

    # --- Database password strength ---
    DB_PASS=$(grep -E "^DB_PASSWORD=" .env 2>/dev/null | cut -d= -f2)
    if [[ ${#DB_PASS} -lt 12 ]]; then
        fail "DB_PASSWORD is too short (${#DB_PASS} chars). Use ≥16 random characters."
    else
        pass "DB_PASSWORD length acceptable"
    fi

    # --- DB_USER=root ---
    DB_USER=$(grep -E "^DB_USER=" .env 2>/dev/null | cut -d= -f2)
    if [[ "$DB_USER" == "root" ]]; then
        fail "DB_USER=root — applications must not connect as the database superuser.
        Create a dedicated DB user with only SELECT/INSERT/UPDATE/DELETE on the app db."
    else
        pass "DB_USER is not root: $DB_USER"
    fi

    # --- Email credentials in plain text ---
    if grep -qE "^EMAIL_HOST_PASSWORD=" .env 2>/dev/null; then
        EPWD=$(grep -E "^EMAIL_HOST_PASSWORD=" .env | cut -d= -f2)
        if [[ -n "$EPWD" && "$EPWD" != '""' && "$EPWD" != "''" ]]; then
            warn "EMAIL_HOST_PASSWORD is set in plain text in .env.
            Ensure .env is NOT committed to version control and is mode 600."
        fi
    fi

    # --- Ngrok auth token ---
    if grep -qE "^NGROK_AUTHTOKEN=" .env 2>/dev/null; then
        warn "NGROK_AUTHTOKEN is present in .env.
        Ngrok should NEVER be used in production — it bypasses your firewall/reverse proxy."
    fi

    # --- .env file permissions ---
    if [[ -f .env ]]; then
        PERMS=$(stat -c "%a" .env 2>/dev/null)
        if [[ "$PERMS" != "600" && "$PERMS" != "400" ]]; then
            fail ".env file permissions are $PERMS — must be 600 (owner read/write only)."
            [[ $FIX_MODE -eq 1 ]] && chmod 600 .env && warn "Auto-patched: chmod 600 .env"
        else
            pass ".env file permissions are $PERMS"
        fi
    fi

    # --- .env committed to git? ---
    if git -C . ls-files --error-unmatch .env &>/dev/null 2>&1; then
        fail ".env IS tracked by git! Run: git rm --cached .env && echo '.env' >> .gitignore"
    else
        pass ".env is not tracked by git"
    fi
}

# ============================================================
# 1. DJANGO DEBUG / PROFILER ENDPOINTS
# ============================================================
check_debug_endpoints() {
    section "1 · Debug & Profiler Endpoint Exposure"

    local debug_urls=(
        "__debug__/"
        "debug/"
        "debug_toolbar/"
        "_profiler/"
        "silk/"
        ".env"
        "settings.py"
        "django.log"
    )

    info "Probing $TARGET for exposed debug interfaces..."
    for ep in "${debug_urls[@]}"; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/${ep}")
        BODY_LEN=$(curl -s -m 5 "${TARGET}/${ep}" | wc -c)
        if [[ "$HTTP_CODE" == "200" && "$BODY_LEN" -gt 200 ]]; then
            fail "DEBUG ENDPOINT ACCESSIBLE: ${TARGET}/${ep} (HTTP $HTTP_CODE, ${BODY_LEN} bytes)
            Immediate action: set DEBUG=False in .env and remove debug-only INSTALLED_APPS
            (debug_toolbar, silk) from production settings."
        else
            pass "Not exposed: /${ep} (HTTP $HTTP_CODE)"
        fi
    done
}

# ============================================================
# 2. SECURITY RESPONSE HEADERS
# ============================================================
check_security_headers() {
    section "2 · HTTP Security Headers"

    HEADERS=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null)

    check_header() {
        local header="$1"; local desc="$2"
        if echo "$HEADERS" | grep -qi "^${header}:"; then
            pass "Header present: $header"
        else
            fail "Missing header: $header — $desc"
        fi
    }

    check_header "X-Content-Type-Options"      "Prevents MIME-sniffing attacks"
    check_header "X-Frame-Options"             "Prevents clickjacking via iframes"
    check_header "X-XSS-Protection"            "Legacy XSS filter for older browsers"
    check_header "Referrer-Policy"             "Controls referrer data leakage"
    check_header "Strict-Transport-Security"   "Forces HTTPS (check only in prod/TLS)"
    check_header "Cross-Origin-Opener-Policy"  "Mitigates cross-origin info leaks"

    # Server header should NOT reveal stack info
    SERVER=$(echo "$HEADERS" | grep -i "^Server:" | head -1)
    if echo "$SERVER" | grep -qi "CPython\|Django\|Werkzeug\|Python"; then
        fail "Server header leaks technology stack: $SERVER
        Add SERVER_HEADER to nginx config to hide the backend version."
    else
        pass "Server header does not leak framework info"
    fi
}

# ============================================================
# 3. ADMIN PANEL EXPOSURE
# ============================================================
check_admin_panel() {
    section "3 · Admin Panel Access Controls"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/admin/")
    if [[ "$HTTP_CODE" == "200" ]]; then
        pass "Admin login page is accessible (HTTP 200) — this is normal, but verify:"
        warn "  - Admin URL should be changed from /admin/ to something non-guessable in production"
        warn "  - Rate limiting / IP allowlist should be applied to the admin URL"
    elif [[ "$HTTP_CODE" == "302" ]]; then
        pass "Admin redirects to login (HTTP 302)"
    else
        info "Admin endpoint returned HTTP $HTTP_CODE"
    fi

    # Check if admin is accessible without auth (misconfiguration)
    BODY=$(curl -s -m 5 "${TARGET}/admin/auth/user/")
    if echo "$BODY" | grep -qi "Django administration" && ! echo "$BODY" | grep -qi "login"; then
        fail "CRITICAL: Admin user list accessible without authentication!"
    fi

    # Brute-force rate limiting check
    info "Testing admin login rate limiting (5 rapid attempts)..."
    for i in {1..5}; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 -X POST "${TARGET}/admin/login/" \
            -d "username=admin&password=wrongpassword${i}" 2>/dev/null)
    done
    FINAL_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 -X POST "${TARGET}/admin/login/" \
        -d "username=admin&password=wrongpassword_final" 2>/dev/null)
    if [[ "$FINAL_CODE" == "429" || "$FINAL_CODE" == "403" ]]; then
        pass "Admin login rate limiting active (HTTP $FINAL_CODE after repeated attempts)"
    else
        warn "No rate limiting detected on admin login (got HTTP $FINAL_CODE after 6 attempts).
        Add django-axes or fail2ban to block repeated login attempts."
    fi
}

# ============================================================
# 4. CSRF PROTECTION
# ============================================================
check_csrf() {
    section "4 · CSRF Protection"

    # Test that POST without CSRF token is rejected
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 -X POST "${TARGET}/login/" \
        -d "username=test&password=test" 2>/dev/null)
    if [[ "$HTTP_CODE" == "403" ]]; then
        pass "CSRF protection active: POST without token returns 403"
    elif [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
        fail "CSRF may not be enforced: POST without CSRF token returned HTTP $HTTP_CODE.
        Verify django.middleware.csrf.CsrfViewMiddleware is in MIDDLEWARE."
    else
        info "CSRF test returned HTTP $HTTP_CODE (check manually)"
    fi

    # CSRF_COOKIE_HTTPONLY should be False (normal for Django)
    info "Note: Django requires CSRF_COOKIE_HTTPONLY=False so JS can read the token — this is correct."
}

# ============================================================
# 5. SENSITIVE FILES / MEDIA DIRECTORY
# ============================================================
check_sensitive_files() {
    section "5 · Sensitive File / Directory Exposure"

    local sensitive_paths=(
        ".env"
        ".env.example"
        ".gitignore"
        "requirements.txt"
        "settings.py"
        "django.log"
        "manage.py"
        "docker-compose.yml"
        "Dockerfile"
        "README.md"
        "DEVELOPER_DOCS.md"
        "media/notifications/"
        "media/timetable_logos/"
        "feasibility_reports/"
    )

    for path in "${sensitive_paths[@]}"; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/${path}")
        if [[ "$HTTP_CODE" == "200" ]]; then
            BODY_LEN=$(curl -s -m 5 "${TARGET}/${path}" | wc -c)
            if [[ "$BODY_LEN" -gt 50 ]]; then
                fail "SENSITIVE FILE ACCESSIBLE: ${TARGET}/${path} (${BODY_LEN} bytes)
                Action: add Nginx deny rules for these paths; never serve project-root files via MEDIA_ROOT."
            fi
        else
            pass "Not exposed: /${path} (HTTP $HTTP_CODE)"
        fi
    done

    # Media directory listing
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/media/")
    BODY=$(curl -s -m 5 "${TARGET}/media/" 2>/dev/null)
    if echo "$BODY" | grep -qi "Index of\|Directory listing"; then
        fail "Media directory listing enabled at /media/ — disable autoindex in Nginx."
    fi
}

# ============================================================
# 6. SQL INJECTION
# ============================================================
check_sql_injection() {
    section "6 · SQL Injection"

    local test_endpoints=(
        "/?id="
        "/?search="
        "/?q="
        "/?user_id="
        "/api/?id="
    )
    local payloads=(
        "'"
        "1 OR 1=1"
        "' OR '1'='1"
        "'; DROP TABLE auth_user--"
        "1 UNION SELECT 1,2,3--"
    )

    FOUND=0
    for ep in "${test_endpoints[@]}"; do
        for pl in "${payloads[@]}"; do
            ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pl" 2>/dev/null || echo "$pl")
            RESP=$(curl -s -m 5 "${TARGET}${ep}${ENC}" 2>/dev/null)
            if echo "$RESP" | grep -qiE "syntax error|mysql|sqlite|psql|pg_|OperationalError|ProgrammingError|django.db"; then
                fail "SQL INJECTION INDICATOR at ${TARGET}${ep} with payload: $pl
                Django ORM generally protects against raw SQLi, but check raw SQL in views."
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No SQL injection indicators found on standard parameter endpoints"
}

# ============================================================
# 7. PATH TRAVERSAL
# ============================================================
check_path_traversal() {
    section "7 · Path Traversal"

    local traversal_payloads=(
        "../../../../etc/passwd"
        "....//....//....//etc/passwd"
        "%2e%2e%2f%2e%2e%2fetc%2fpasswd"
        "..%252f..%252fetc%252fpasswd"
    )
    local test_params=("file" "path" "name" "template" "doc" "download" "img")

    FOUND=0
    for param in "${test_params[@]}"; do
        for pl in "${traversal_payloads[@]}"; do
            RESP=$(curl -s -m 5 "${TARGET}/?${param}=${pl}" 2>/dev/null)
            if echo "$RESP" | grep -qE "root:(x|!|\*):0:0|/bin/bash|/sbin/nologin"; then
                fail "PATH TRAVERSAL at ?${param}= with payload: $pl — /etc/passwd readable!"
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No path traversal indicators found on common parameter names"
}

# ============================================================
# 8. OPEN REDIRECT
# ============================================================
check_open_redirect() {
    section "8 · Open Redirect"

    local redirect_payloads=(
        "//evil.com"
        "https://evil.com"
        "//evil.com/%2F.."
        "/\\evil.com"
    )
    local redirect_params=("next" "redirect" "url" "return" "goto" "callback")

    FOUND=0
    for param in "${redirect_params[@]}"; do
        for pl in "${redirect_payloads[@]}"; do
            LOCATION=$(curl -s -I -m 5 -L "${TARGET}/login/?${param}=${pl}" 2>/dev/null \
                | grep -i "^Location:" | tail -1 | cut -d' ' -f2)
            if echo "$LOCATION" | grep -qi "evil\.com"; then
                fail "OPEN REDIRECT: ?${param}=${pl} redirects to: $LOCATION
                Django's safe_redirect_url check may not cover all cases; audit all views using 'next' param."
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No open redirect detected on common redirect parameters"
}

# ============================================================
# 9. COMMAND INJECTION
# ============================================================
check_command_injection() {
    section "9 · Command Injection"

    local cmd_payloads=(
        "; cat /etc/passwd"
        "| id"
        "\`id\`"
        "\$(id)"
        "127.0.0.1; id"
    )
    local params=("ip" "host" "cmd" "ping" "url" "address" "exec")

    FOUND=0
    for param in "${params[@]}"; do
        for pl in "${cmd_payloads[@]}"; do
            ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pl" 2>/dev/null || echo "$pl")
            RESP=$(curl -s -m 5 "${TARGET}/?${param}=${ENC}" 2>/dev/null)
            if echo "$RESP" | grep -qE "uid=[0-9]+|root:|/bin/bash|Linux.*#"; then
                fail "COMMAND INJECTION at ?${param}= with payload: $pl"
                FOUND=1
            fi
        done
    done
    [[ $FOUND -eq 0 ]] && pass "No command injection indicators found"
}

# ============================================================
# 10. COOKIE SECURITY FLAGS
# ============================================================
check_cookie_security() {
    section "10 · Cookie Security Flags"

    COOKIE_HEADER=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null | grep -i "Set-Cookie")

    if [[ -z "$COOKIE_HEADER" ]]; then
        info "No Set-Cookie header on home page (cookies may be set after login)"
    else
        echo "$COOKIE_HEADER" | while IFS= read -r cookie; do
            NAME=$(echo "$cookie" | cut -d= -f1 | sed 's/Set-Cookie://i' | tr -d ' ')
            if ! echo "$cookie" | grep -qi "HttpOnly"; then
                fail "Cookie missing HttpOnly flag: $cookie"
            else
                pass "Cookie has HttpOnly: $NAME"
            fi
            if ! echo "$cookie" | grep -qi "SameSite"; then
                warn "Cookie missing SameSite attribute: $cookie"
            fi
        done
    fi

    # Session cookie should be Secure in production (needs HTTPS)
    info "Note: SESSION_COOKIE_SECURE and CSRF_COOKIE_SECURE are only enforced when DEBUG=False in settings.py"
}

# ============================================================
# 11. INFORMATION DISCLOSURE
# ============================================================
check_info_disclosure() {
    section "11 · Information Disclosure"

    # Django 404 page — should not show URLs in production
    RESP_404=$(curl -s -m 5 "${TARGET}/this-page-does-not-exist-zxqyuv/" 2>/dev/null)
    if echo "$RESP_404" | grep -qi "You're seeing this error because you have DEBUG"; then
        fail "Django debug 404 page is active — reveals all URL patterns to anyone.
        Set DEBUG=False to use the custom 404 handler."
    elif echo "$RESP_404" | grep -qi "Page not found"; then
        pass "Custom or minimal 404 page returned (debug 404 not active)"
    fi

    # Stack traces / internal errors
    RESP_500=$(curl -s -m 5 "${TARGET}/trigger_500_test_xyzqv/" 2>/dev/null)
    if echo "$RESP_500" | grep -qi "Traceback\|File \"/"; then
        fail "Stack trace visible in error response — set DEBUG=False and configure ADMINS."
    else
        pass "No stack trace visible in error responses"
    fi

    # Email addresses in source (info@chuka.ac.ke was extracted by the test)
    RESP_HOME=$(curl -s -m 5 "${TARGET}/" 2>/dev/null)
    if echo "$RESP_HOME" | grep -qE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"; then
        EMAILS=$(echo "$RESP_HOME" | grep -oE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" | sort -u)
        warn "Email address(es) visible in page source (scraped by the exploit): $EMAILS
        Consider obfuscating contact emails using JS rendering or a contact form."
    else
        pass "No plaintext email addresses found in home page source"
    fi
}

# ============================================================
# 12. RATE LIMITING & DOS RESILIENCE
# ============================================================
check_rate_limiting() {
    section "12 · Rate Limiting & DoS Resilience"

    info "Sending 20 rapid requests to the login endpoint..."
    BLOCKED=0
    for i in $(seq 1 20); do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 2 "${TARGET}/login/" 2>/dev/null)
        if [[ "$CODE" == "429" || "$CODE" == "503" ]]; then
            BLOCKED=1
            break
        fi
    done

    if [[ $BLOCKED -eq 1 ]]; then
        pass "Rate limiting active — server returned 429/503 after repeated requests"
    else
        warn "No rate limiting detected after 20 rapid login requests.
        Recommendations:
          - Add django-axes for login attempt throttling
          - Configure Nginx/Gunicorn rate limits (limit_req_zone)
          - Add Cloudflare or equivalent WAF in front of the app"
    fi
}

# ============================================================
# 13. TLS / HTTPS
# ============================================================
check_tls() {
    section "13 · TLS / HTTPS"

    if echo "$TARGET" | grep -q "^https://"; then
        # Check HSTS
        HSTS=$(curl -s -I -m 5 "${TARGET}/" 2>/dev/null | grep -i "Strict-Transport-Security")
        if [[ -n "$HSTS" ]]; then
            pass "HSTS header present: $HSTS"
        else
            fail "HSTS header missing on HTTPS endpoint. Add SECURE_HSTS_SECONDS=31536000 (requires DEBUG=False)"
        fi

        # Check for HTTP → HTTPS redirect
        HTTP_TARGET=$(echo "$TARGET" | sed 's/^https/http/')
        REDIRECT_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "$HTTP_TARGET" 2>/dev/null)
        if [[ "$REDIRECT_CODE" == "301" || "$REDIRECT_CODE" == "302" ]]; then
            pass "HTTP redirects to HTTPS (HTTP $REDIRECT_CODE)"
        else
            fail "HTTP endpoint does not redirect to HTTPS (got $REDIRECT_CODE). Set SECURE_SSL_REDIRECT=True"
        fi
    else
        warn "Target is not HTTPS ($TARGET).
        In production: use Nginx to terminate TLS and reverse-proxy to Gunicorn.
        Set SECURE_SSL_REDIRECT=True, SESSION_COOKIE_SECURE=True, CSRF_COOKIE_SECURE=True in .env."
    fi
}

# ============================================================
# 14. MEDIA & STATIC FILE SERVING
# ============================================================
check_media_static() {
    section "14 · Media / Static File Serving"

    # Django should NOT serve media in production (settings.py does this via urlpatterns)
    MEDIA_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/media/" 2>/dev/null)
    if [[ "$MEDIA_CODE" == "200" ]]; then
        warn "Media root is accessible at /media/.
        In production, Nginx should serve /media/ directly and Django should NOT add
        the static/media URL routes (remove the urlpatterns += static(...) blocks for production)."
    fi

    # PDF files in media/notifications should not be publicly listable
    NOTIF_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/media/notifications/" 2>/dev/null)
    NOTIF_BODY=$(curl -s -m 5 "${TARGET}/media/notifications/" 2>/dev/null)
    if echo "$NOTIF_BODY" | grep -qi "\.pdf\|Index of"; then
        fail "Notification PDFs are browsable at /media/notifications/ — these may contain
        sensitive timetabling and staff data. Restrict with Nginx auth or move outside MEDIA_ROOT."
    fi
}

# ============================================================
# 15. SOURCE CODE / VERSION CONTROL EXPOSURE
# ============================================================
check_vcs_exposure() {
    section "15 · Version Control & Source Code Exposure"

    local vcs_paths=(".git/config" ".git/HEAD" ".svn/entries" ".hg/hgrc" ".DS_Store")
    for path in "${vcs_paths[@]}"; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/${path}")
        if [[ "$CODE" == "200" ]]; then
            fail "VCS FILE ACCESSIBLE: ${TARGET}/${path}
            This can expose the full source code. Block in Nginx:
              location ~ /\\.git { deny all; }"
        else
            pass "Not exposed: /${path} (HTTP $CODE)"
        fi
    done
}

# ============================================================
# 16. API ENDPOINT AUTHENTICATION
# ============================================================
check_api_auth() {
    section "16 · API Endpoint Authentication"

    local api_endpoints=(
        "api/"
        "api/v1/"
    )

    for ep in "${api_endpoints[@]}"; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TARGET}/${ep}")
        BODY=$(curl -s -m 5 "${TARGET}/${ep}" 2>/dev/null)
        if [[ "$CODE" == "200" ]] && echo "$BODY" | grep -qiE "user|email|password|token|data"; then
            fail "API endpoint /${ep} returns data without authentication (HTTP $CODE).
            All API views must use @login_required or DRF permission classes."
        elif [[ "$CODE" == "401" || "$CODE" == "403" || "$CODE" == "302" ]]; then
            pass "API endpoint /${ep} requires auth (HTTP $CODE)"
        else
            info "API endpoint /${ep}: HTTP $CODE"
        fi
    done
}

# ============================================================
# FINAL SUMMARY
# ============================================================
print_summary() {
    section "SECURITY AUDIT SUMMARY"

    TOTAL=$((FAIL_COUNT + WARN_COUNT + PASS_COUNT))
    log ""
    log "${BOLD}  Total checks : $TOTAL${NC}"
    log "${GREEN}  Passed       : $PASS_COUNT${NC}"
    log "${YELLOW}  Warnings     : $WARN_COUNT${NC}"
    log "${RED}  Failures     : $FAIL_COUNT${NC}"
    log ""
    log "  Full report saved to: ${BOLD}$REPORT_FILE${NC}"
    log ""

    if [[ $FAIL_COUNT -gt 0 ]]; then
        log "${RED}${BOLD}  ✗ DO NOT DEPLOY — $FAIL_COUNT critical issue(s) must be resolved first.${NC}"
        exit 1
    elif [[ $WARN_COUNT -gt 0 ]]; then
        log "${YELLOW}${BOLD}  ⚠  REVIEW BEFORE DEPLOY — $WARN_COUNT warning(s) should be addressed.${NC}"
        exit 0
    else
        log "${GREEN}${BOLD}  ✓ All checks passed — system is ready for production deployment.${NC}"
        exit 0
    fi
}

# ============================================================
# MAIN
# ============================================================
log "  University Timetable System — Security Audit"
log "  Target : $TARGET"
log "  Date   : $(date)"
log "  Fix mode: $([[ $FIX_MODE -eq 1 ]] && echo 'ON (auto-patching enabled)' || echo 'OFF (read-only)')"

check_env_file
check_debug_endpoints
check_security_headers
check_admin_panel
check_csrf
check_sensitive_files
check_sql_injection
check_path_traversal
check_open_redirect
check_command_injection
check_cookie_security
check_info_disclosure
check_rate_limiting
check_tls
check_media_static
check_vcs_exposure
check_api_auth

print_summary