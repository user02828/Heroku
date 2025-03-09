#!/bin/bash
set -e

# Lista de utilitários proibidos por segurança
FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Função para manter o container ativo em ambientes de hospedagem como Render
keep_alive_local() {
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        echo "RENDER_EXTERNAL_HOSTNAME não definido. Encerrando."
        exit 1
    fi
    while true; do
        curl -s "https://$RENDER_EXTERNAL_HOSTNAME" -o /dev/null || echo "Falha ao acessar $RENDER_EXTERNAL_HOSTNAME"
        sleep 30
    done
}
keep_alive_local &

# Função para monitorar e remover ferramentas proibidas (se houver)
monitor_forbidden() {
    while true; do
        for cmd in $FORBIDDEN_UTILS; do
            if command -v "$cmd" >/dev/null 2>&1; then
                echo "Removendo $cmd por questões de segurança..."
                apt-get purge -y "$cmd" 2>/dev/null || true
            fi
        done
        sleep 10
    done
}
monitor_forbidden &

# Execução do aplicativo principal
exec python -m hikka --port 8080