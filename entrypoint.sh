#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

PORT=${PORT:-8080}
HIKKA_RESTART_TIMEOUT=60

# Устанавливаем зависимости
apt-get update
apt-get install -y net-tools  # Устанавливаем netstat
pip install flask requests

if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
    RENDER_EXTERNAL_HOSTNAME=$(curl -s "http://169.254.169.254/latest/meta-data/public-hostname" || echo "")
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        exit 1
    fi
fi

python3 - <<EOF
from flask import Flask
import requests
import subprocess
import time
import threading
import logging
import sys
import shutil
import os

# Настройка логирования
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
    """Освобождаем порт, если он занят"""
    try:
        output = subprocess.check_output(f"netstat -tulnp | grep :{port}", shell=True).decode()
        pid = output.split()[-1].split('/')[0]
        if pid:
            subprocess.run(f"kill -9 {pid}", shell=True)
            logger.info(f"Убит процесс (PID: {pid}), занимавший порт {port}")
            time.sleep(1)  # Даём время на освобождение
    except subprocess.CalledProcessError:
        logger.info(f"Порт {port} уже свободен или процесс не найден")
    except Exception as e:
        logger.error(f"Ошибка при освобождении порта: {e}")

def start_hikka():
    global hikka_process, current_mode
    free_port($PORT)  # Освобождаем порт перед запуском
    try:
        hikka_process = subprocess.Popen(["python", "-m", "hikka", "--port", str($PORT)])
        logger.info(f"Хикка запущена с PID: {hikka_process.pid}")
        current_mode = "hikka"
    except Exception as e:
        logger.error(f"Ошибка при запуске Хикки: {e}")
        hikka_process = None

def stop_hikka():
    global hikka_process
    if hikka_process and hikka_process.poll() is None:
        hikka_process.kill()
        logger.info(f"Хикка (PID: {hikka_process.pid}) остановлена")
    hikka_process = None

def monitor_hikka():
    global hikka_last_seen, current_mode
    while True:
        time.sleep(10)
        if hikka_process and hikka_process.poll() is None:
            hikka_last_seen = time.time()
        else:
            logger.warning(f"Процесс Хикки умер (PID: {hikka_process.pid if hikka_process else 'None'})")
            if time.time() - hikka_last_seen > $HIKKA_RESTART_TIMEOUT:
                stop_hikka()
                start_hikka()
                if current_mode == "flask" and hikka_process and hikka_process.poll() is None:
                    logger.info("Хикка вернулась, завершаем Flask")
                    os._exit(0)

def keep_alive_local():
    while True:
        time.sleep(30)
        try:
            requests.get(f"https://$RENDER_EXTERNAL_HOSTNAME", timeout=5)
        except requests.exceptions.RequestException:
            pass

def monitor_forbidden():
    forbidden_utils = "$FORBIDDEN_UTILS".split()
    while True:
        for cmd in forbidden_utils:
            if shutil.which(cmd):
                subprocess.run(["apt-get", "purge", "-y", cmd], check=False)
        time.sleep(10)

# Запуск фоновых задач
threading.Thread(target=monitor_hikka, daemon=True).start()
threading.Thread(target=keep_alive_local, daemon=True).start()
threading.Thread(target=monitor_forbidden, daemon=True).start()

# Основной цикл
start_hikka()
while True:
    if current_mode == "hikka":
        if hikka_process and hikka_process.poll() is None:
            time.sleep(10)
        else:
            current_mode = "flask"
            logger.info("Переключение на Flask из-за смерти Хикки")
    if current_mode == "flask":
        logger.info("Запуск Flask в качестве заглушки")
        app.run(host="0.0.0.0", port=$PORT)

@app.route("/healthz")
def healthz():
    try:
        response = requests.get(f"http://localhost:$PORT", timeout=3)
        if response.status_code == 200:
            return "OK", 200
    except requests.exceptions.RequestException:
        return "DOWN", 500
EOF
