#!/bin/bash
set -e

PORT=${PORT:-8080}
HIKKA_RESTART_TIMEOUT=60

if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
    RENDER_EXTERNAL_HOSTNAME=$(curl -s "http://169.254.169.254/latest/meta-data/public-hostname" || echo "")
    [ -z "$RENDER_EXTERNAL_HOSTNAME" ] && exit 1
fi

python3 - <<EOF
import os
import time
import threading
import subprocess
import logging
import requests
from flask import Flask

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger()

app = Flask(__name__)
hikka_process = None
hikka_last_seen = time.time()
current_mode = "hikka"

def free_port(port):
    try:
        output = subprocess.check_output(f"netstat -tulnp | grep :{port}", shell=True).decode()
        pid = output.split()[-1].split('/')[0]
        if pid:
            subprocess.run(f"kill -9 {pid}", shell=True)
            logger.info(f"Porta {port} liberada, processo encerrado PID {pid}")
            time.sleep(1)
    except subprocess.CalledProcessError:
        logger.info(f"Porta {port} já está livre")
    except Exception as e:
        logger.error(f"Erro ao liberar a porta: {e}")

def start_hikka():
    global hikka_process, current_mode
    free_port($PORT)
    try:
        hikka_process = subprocess.Popen(["python", "-m", "hikka", "--port", str($PORT)])
        logger.info(f"Hikka iniciada, PID: {hikka_process.pid}")
        current_mode = "hikka"
    except Exception as e:
        logger.error(f"Erro ao iniciar: {e}")
        hikka_process = None

def stop_hikka():
    global hikka_process
    if hikka_process and hikka_process.poll() is None:
        hikka_process.kill()
        logger.info("Hikka parada")
    hikka_process = None

def monitor_hikka():
    global hikka_last_seen, current_mode
    while True:
        time.sleep(10)
        if hikka_process and hikka_process.poll() is None:
            hikka_last_seen = time.time()
        elif time.time() - hikka_last_seen > $HIKKA_RESTART_TIMEOUT:
            logger.warning("Hikka não está respondendo, alternando para Flask...")
            stop_hikka()
            current_mode = "flask"
        
        if current_mode == "flask" and hikka_process is None:
            start_hikka()
            if hikka_process and hikka_process.poll() is None:
                logger.info("Hikka restaurada, encerrando Flask")
                os._exit(0)

@app.route("/healthz")
def healthz():
    try:
        response = requests.get(f"http://localhost:$PORT", timeout=3)
        if response.status_code == 200:
            return "OK", 200
    except requests.exceptions.RequestException:
        return "DOWN", 500

threading.Thread(target=monitor_hikka, daemon=True).start()
start_hikka()

if current_mode == "flask":
    logger.info("Iniciando Flask como servidor reserva")
    app.run(host="127.0.0.1", port=$PORT)
EOF