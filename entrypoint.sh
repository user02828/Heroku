#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

PORT=${PORT:-8080}
HIKKA_RESTART_TIMEOUT=60

# Instalação de dependências
apt-get update
apt-get install -y net-tools
pip install --no-cache-dir flask requests

if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
    RENDER_EXTERNAL_HOSTNAME=$(curl -s "http://169.254.169.254/latest/meta-data/public-hostname" || echo "")
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        exit 1
    fi
fi

python3 - <<'EOF'
from flask import Flask
import requests
import subprocess
import time
import threading
import shutil
import os
import re
import logging

# Configuração de log para saída no terminal
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger()

app = Flask(__name__)
hikka_process = None
current_mode = "hikka"
hikka_last_seen = time.time()

def free_port(port):
    """Libera o porto se estiver ocupado"""
    try:
        # Listamos as conexões ativas e procuramos o porto desejado
        output = subprocess.check_output(f"netstat -tulnp | grep :{port}", shell=True, text=True)
        match = re.search(r"(\d+)/", output)
        if match:
            pid = match.group(1)
            if pid.isdigit():
                subprocess.run(f"kill -9 {pid}", shell=True, check=False)
                logger.info(f"Processo (PID: {pid}) que usava a porta {port} foi encerrado")
                time.sleep(1)
    except subprocess.CalledProcessError:
        logger.info(f"Porta {port} está livre")

def start_hikka():
    global hikka_process, current_mode
    free_port({{PORT}})
    try:
        hikka_process = subprocess.Popen(["python3", "-m", "hikka", "--port", str({{PORT}})])
        logger.info(f"Hikka iniciada (PID: {hikka_process.pid})")
        current_mode = "hikka"
    except Exception as e:
        logger.error(f"Erro ao iniciar Hikka: {e}")
        hikka_process = None

def stop_hikka():
    global hikka_process
    if hikka_process and hikka_process.poll() is None:
        hikka_process.kill()
        logger.info(f"Hikka (PID: {hikka_process.pid}) foi encerrada")
    hikka_process = None

def monitor_hikka():
    global hikka_last_seen, current_mode
    while True:
        time.sleep(10)
        if hikka_process and hikka_process.poll() is None:
            hikka_last_seen = time.time()
        else:
            logger.warning(f"Processo Hikka morreu (PID: {hikka_process.pid if hikka_process else 'None'})")
            if time.time() - hikka_last_seen > {{HIKKA_RESTART_TIMEOUT}}:
                stop_hikka()
                start_hikka()
                # Se estivermos em modo Flask e Hikka voltar, encerramos o Flask
                if current_mode == "flask" and hikka_process and hikka_process.poll() is None:
                    logger.info("Hikka recuperada; finalizando Flask")
                    os._exit(0)

def keep_alive_local():
    while True:
        time.sleep(30)
        try:
            requests.get(f"https://{os.environ.get('RENDER_EXTERNAL_HOSTNAME')}", timeout=5)
        except requests.exceptions.RequestException:
            pass

def monitor_forbidden():
    forbidden_utils = """{FORBIDDEN_UTILS}""".split()
    while True:
        for cmd in forbidden_utils:
            if shutil.which(cmd):
                subprocess.run(["apt-get", "purge", "-y", cmd], check=False)
                logger.info(f"Utilitário proibido removido: {cmd}")
        time.sleep(10)

# Inicializa tarefas em background
threading.Thread(target=monitor_hikka, daemon=True).start()
threading.Thread(target=keep_alive_local, daemon=True).start()
threading.Thread(target=monitor_forbidden, daemon=True).start()

# Loop principal
start_hikka()
while True:
    if current_mode == "hikka":
        if hikka_process and hikka_process.poll() is None:
            time.sleep(10)
        else:
            current_mode = "flask"
            logger.info("Mudando para Flask devido à falha do Hikka")
    if current_mode == "flask":
        logger.info("Executando Flask como fallback")
        app.run(host="127.0.0.1", port={{PORT}})

@app.route("/healthz")
def healthz():
    try:
        response = requests.get(f"http://localhost:{{PORT}}", timeout=3)
        if response.status_code == 200:
            return "OK", 200
    except requests.exceptions.RequestException:
        return "DOWN", 500
EOF