#!/bin/bash
set -e

FORBIDDEN="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

PORT=${PORT:-8080}

keep_alive_local() {
    while true; do
        sleep 30
        curl -s --max-time 10 "https://$KOYEB_PUBLIC_DOMAIN" >/dev/null
    done
}

monitor_forbidden() {
    while true; do
        for cmd in $FORBIDDEN; do
            command -v "$cmd" >/dev/null 2>&1 && echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] Обнаружена запрещенная утилита: $cmd" && apt-get purge -y "$cmd" >/dev/null 2>&1
        done
        sleep 10
    done
}

start_heroku() {
    python3 -m hikka --port "$PORT" &
}

start_heroku
keep_alive_local &
monitor_forbidden &

tail -f /dev/null
