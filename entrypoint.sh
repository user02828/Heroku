#!/bin/bash
set -e

# Lista de utilitários proibidos para segurança
FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Porta definida pelo Render (ou 8080 por padrão)
PORT=${PORT:-8080}
HIKKA_RESTART_TIMEOUT=60

# Instalando dependências apenas se necessário
if ! command -v netstat &> /dev/null; then
    apt-get update
    apt-get install -y net-tools  # Para netstat
fi

# Instalando dependências do Python (garantindo que Flask esteja disponível)
pip install --no-cache-dir flask requests

# Definindo hostname do Render (se não estiver presente, ignora)
if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
    RENDER_EXTERNAL_HOSTNAME=$(curl -s "http://169.254.169.254/latest/meta-data/public-hostname" || echo "localhost")
fi

# Rodando código Python
python3 - <<EOF
import os
import time
import threading
import logging
import subprocess
import shutil
import requests
from flask import Flask

# Configuração de logs
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger()

# Obtendo configurações de ambiente
PORT = os.getenv("PORT", "8080")
HIKKA_RESTART_TIMEOUT = int(os.getenv("HIKKA_RESTART_TIMEOUT", "60"))
RENDER_EXTERNAL_HOSTNAME = os.getenv("RENDER_EXTERNAL_HOSTNAME", "localhost")

app = Flask(__name__)
hikka_process = None
hikka_last_seen = time.time()

def free_port(port):
    """Libera a porta se estiver ocupada"""
    try:
        output = subprocess.check_output(f"netstat -tulnp | grep :{port}", shell=True).decode()
        pid = output.split()[-1].split('/')[0]
        if pid:
            subprocess.run(f"kill -9 {pid}", shell=True)
            logger.info(f"Processo (PID: {pid}) foi encerrado para liberar a porta {port}")
            time.sleep(1)  # Aguarda a liberação completa
    except subprocess.CalledProcessError:
        logger.info(f"Porta {port} já está livre ou nenhum processo foi encontrado")
    except Exception as e:
        logger.error(f"Erro ao liberar porta: {e}")

def start_hikka():
    """Inicia o processo do Hikka"""
    global hikka_process
    free_port(PORT)  # Garante que a porta esteja livre antes de iniciar
    try:
        hikka_process = subprocess.Popen(["python", "-m", "hikka", "--port", str(PORT)])
        logger.info(f"Hikka iniciado com PID: {hikka_process.pid}")
    except Exception as e:
        logger.error(f"Erro ao iniciar Hikka: {e}")
        hikka_process = None

def stop_hikka():
    """Encerra o processo do Hikka"""
    global hikka_process
    if hikka_process and hikka_process.poll() is None:
        hikka_process.kill()
        logger.info(f"Hikka (PID: {hikka_process.pid}) foi encerrado")
    hikka_process = None

def monitor_hikka():
    """Monitora o Hikka e reinicia se necessário"""
    global hikka_last_seen
    while True:
        time.sleep(10)
        if hikka_process and hikka_process.poll() is None:
            hikka_last_seen = time.time()
        else:
            logger.warning(f"Hikka morreu (PID: {hikka_process.pid if hikka_process else 'None'})")
            if time.time() - hikka_last_seen > HIKKA_RESTART_TIMEOUT:
                stop_hikka()
                start_hikka()

def keep_alive_local():
    """Mantém a aplicação acessível localmente"""
    while True:
        time.sleep(30)
        try:
            requests.get(f"http://{RENDER_EXTERNAL_HOSTNAME}", timeout=5)
        except requests.exceptions.RequestException:
            pass

def monitor_forbidden():
    """Verifica e remove ferramentas proibidas"""
    forbidden_utils = "$FORBIDDEN_UTILS".split()
    while True:
        for cmd in forbidden_utils:
            if shutil.which(cmd):
                subprocess.run(["apt-get", "purge", "-y", cmd], check=False)
        time.sleep(10)

# Iniciando tarefas em segundo plano
threading.Thread(target=monitor_hikka, daemon=True).start()
threading.Thread(target=keep_alive_local, daemon=True).start()
threading.Thread(target=monitor_forbidden, daemon=True).start()

# Iniciando Hikka
start_hikka()

# API de Health Check
@app.route("/healthz")
def healthz():
    try:
        response = requests.get(f"http://localhost:{PORT}", timeout=3)
        if response.status_code == 200:
            return "OK", 200
    except requests.exceptions.RequestException:
        return "DOWN", 500

# Executa o Flask como fallback
logger.info("Executando Flask como fallback")
app.run(host="0.0.0.0", port=int(PORT))
EOF