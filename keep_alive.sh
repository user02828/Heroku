#!/bin/bash  
set -e  
  
# --- Configuração do ambiente (Shell) ---  
# Força a porta para 8080 (o Render exige a variável PORT; forçar 8080 pode causar problemas de roteamento)  
export PORT=8080  
export PYTHON_CMD="python3 -m hikka"  
export HEALTH_CHECK_INTERVAL=15  
export STARTUP_DELAY=20  
export RESTART_DELAY=3  
export HIKKA_RESTART_TIMEOUT=60  
export MAX_RESTART_ATTEMPTS=3  
export LOG_FILE=""  # Opcional; se definido, os logs serão gravados neste arquivo  
export RENDER_EXTERNAL_HOSTNAME=""  # Se aplicável  
export FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medea john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"  
export PASS_ROOT_ARG="true"  
  
# Atualiza e instala dependências necessárias (ajuste conforme seu sistema)  
apt-get update  
apt-get install -y net-tools  
pip install --no-cache-dir flask requests  
  
echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] --- FORCING PORT TO ${PORT} --- Ignoring PORT environment variable! This will likely fail on Render."  
  
# --- Bloco Python ---  
python3 - <<'EOF'  
import subprocess  
import time  
import os  
import signal  
import requests  
import logging  
import psutil  
import sys  
import threading  
import shutil  # Para shutil.which  
import socket  # Para verificação de porta  
  
# --- Configuração ---  
PORT = 8080  # Forçando porta 8080 (ignora o ambiente)  
logging.warning(f"--- FORCING PORT TO {PORT} --- Ignoring PORT environment variable! This will likely fail on Render.")  
  
TARGET_URL = f"http://127.0.0.1:{PORT}"  
HEALTH_CHECK_URL = f"http://127.0.0.1:{PORT}/healthz"  
  
PYTHON_CMD = os.environ.get("PYTHON_CMD", "python3 -m hikka").split()  
HEALTH_CHECK_INTERVAL = int(os.environ.get("HEALTH_CHECK_INTERVAL", 15))  
STARTUP_DELAY = int(os.environ.get("STARTUP_DELAY", 20))  
RESTART_DELAY = int(os.environ.get("RESTART_DELAY", 3))  
HIKKA_RESTART_TIMEOUT = int(os.environ.get("HIKKA_RESTART_TIMEOUT", 60))  
MAX_RESTART_ATTEMPTS = int(os.environ.get("MAX_RESTART_ATTEMPTS", 3))  
LOG_FILE = os.environ.get("LOG_FILE", None)  
RENDER_EXTERNAL_HOSTNAME = os.environ.get("RENDER_EXTERNAL_HOSTNAME", "")  
FORBIDDEN_UTILS = os.environ.get("FORBIDDEN_UTILS", "").strip()  
PASS_ROOT_ARG = os.environ.get("PASS_ROOT_ARG", "true").lower() == "true"  
  
# --- Configuração do Logging ---  
log_level_str = os.environ.get("LOG_LEVEL", "INFO").upper()  
log_level = getattr(logging, log_level_str, logging.INFO)  
log_handlers = [logging.StreamHandler(sys.stdout)]  
if LOG_FILE:  
    try:  
        log_handlers.append(logging.FileHandler(LOG_FILE))  
    except Exception as e:  
        print(f"[AVISO] Não foi possível abrir o arquivo de log {LOG_FILE}: {e}", file=sys.stderr)  
logging.basicConfig(  
    level=log_level,  
    format="%(asctime)s [%(levelname)s] (%(threadName)s) %(message)s",  
    handlers=log_handlers  
)  
logging.info(f"Nível de log definido para: {log_level_str}")  
logging.info(f"Porta alvo FORÇADA para Hikka: {PORT}")  
logging.info(f"URL de verificação de saúde interna: {HEALTH_CHECK_URL}")  
logging.info(f"Comando para iniciar Hikka: {' '.join(PYTHON_CMD)}")  
  
# --- Estado Global ---  
hikka_process_obj: psutil.Process | None = None  
monitor_stop_event = threading.Event()  
  
# --- Funções Auxiliares ---  
  
def find_process_by_cmd(cmd):  
    """Encontra o processo Hikka usando psutil, excluindo este script."""  
    cmd_str = " ".join(cmd)  
    logging.debug(f"Procurando processo que contenha: '{cmd_str}'")  
    for proc in psutil.process_iter(['pid', 'cmdline', 'status', 'create_time']):  
        try:  
            proc_cmdline = proc.info.get('cmdline')  
            if proc_cmdline:  
                proc_cmdline_str = " ".join(proc_cmdline)  
                if cmd_str in proc_cmdline_str and "keep_alive.py" not in proc_cmdline_str and proc.info.get('status') != psutil.STATUS_ZOMBIE:  
                    logging.debug(f"Processo Hikka potencial encontrado: PID={proc.pid}, Cmd='{proc_cmdline_str}', Status={proc.info.get('status')}")  
                    if time.time() - proc.info.get('create_time', 0) < 60:  
                        return proc  
                    else:  
                        logging.warning(f"Ignorando processo Hikka antigo encontrado: PID={proc.pid}")  
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess, TypeError):  
            pass  
    logging.debug("Nenhum processo Hikka correspondente encontrado.")  
    return None  
  
def release_port_if_occupied(port):  
    """Libera a porta usando psutil, evitando matar este script."""  
    logging.debug(f"Verificando se a porta {port} está ocupada...")  
    killed_process = False  
    for conn in psutil.net_connections(kind='inet'):  
        if conn.laddr.port == port and conn.status == psutil.CONN_LISTEN and conn.pid:  
            try:  
                proc = psutil.Process(conn.pid)  
                try:  
                    proc_cmdline_str = " ".join(proc.cmdline())  
                except psutil.NoSuchProcess:  
                    continue  
                if "keep_alive.py" not in proc_cmdline_str:  
                    logging.warning(f"Porta {port} ocupada por PID {proc.pid} (Cmd: {proc_cmdline_str}). Tentando encerrar...")  
                    proc.terminate()  
                    try:  
                        proc.wait(timeout=RESTART_DELAY / 2)  
                        logging.info(f"Processo {proc.pid} encerrado (terminate).")  
                        killed_process = True  
                    except psutil.TimeoutExpired:  
                        logging.warning(f"Processo {proc.pid} não encerrou graciosamente. Forçando (kill)...")  
                        proc.kill()  
                        proc.wait(timeout=RESTART_DELAY / 2)  
                        logging.info(f"Processo {proc.pid} encerrado (kill).")  
                        killed_process = True  
                    except psutil.NoSuchProcess:  
                        logging.info(f"Processo {proc.pid} desapareceu após sinal.")  
                        killed_process = True  
                else:  
                    logging.warning(f"Processo keep_alive {proc.pid} segurando a porta {port}. Ignorando.")  
            except psutil.NoSuchProcess:  
                logging.warning(f"Processo {conn.pid} que segurava a porta {port} desapareceu.")  
                killed_process = True  
            except (psutil.AccessDenied, TypeError, Exception) as e:  
                logging.error(f"Falha ao encerrar processo {conn.pid} na porta {port}: {e}")  
                return False  
    if killed_process:  
        logging.info(f"Tentativa de liberar porta {port} concluída.")  
        time.sleep(0.5)  
    else:  
        logging.info(f"Porta {port} parece livre ou não retida por processo eliminável.")  
    return True  
  
def check_port_listening(port, host='127.0.0.1', timeout=1.0):  
    """Tenta uma conexão socket para verificar se a porta está escutando."""  
    logging.debug(f"[VERIFICAÇÃO SOCKET] Tentando conectar a {host}:{port} (timeout {timeout}s)")  
    try:  
        with socket.create_connection((host, port), timeout=timeout) as s:  
            logging.debug(f"[VERIFICAÇÃO SOCKET] Conexão a {host}:{port} bem-sucedida.")  
            return True  
    except (socket.timeout, ConnectionRefusedError, OSError) as e:  
        logging.debug(f"[VERIFICAÇÃO SOCKET] Conexão a {host}:{port} falhou: {e}")  
        return False  
    except Exception as e:  
        logging.exception(f"[VERIFICAÇÃO SOCKET] Erro ao conectar a {host}:{port}: {e}")  
        return False  
  
def start_hikka_process(forced_port):  
    """Inicia o processo Hikka na porta especificada."""  
    global hikka_process_obj  
    logging.info(f"[INICIAR] Tentando iniciar Hikka na porta FORÇADA {forced_port}...")  
    if not release_port_if_occupied(forced_port):  
        logging.error(f"[INICIAR] Não foi possível liberar a porta {forced_port}. Abortando.")  
        return None  
    process = None  
    try:  
        cmd_to_run = PYTHON_CMD + ["--port", str(forced_port)]  
        if PASS_ROOT_ARG:  
            cmd_to_run.append("--root")  
        sub_env = os.environ.copy()  
        sub_env["PORT"] = str(forced_port)  
        logging.info(f"[INICIAR] Ambiente do subprocesso terá PORT={sub_env['PORT']}")  
        logging.info(f"[INICIAR] Executando comando: {' '.join(cmd_to_run)}")  
        process = subprocess.Popen(  
            cmd_to_run,  
            stdout=sys.stdout,  
            stderr=sys.stderr,  
            start_new_session=True,  
            env=sub_env  
        )  
        logging.info(f"[INICIAR] Processo Hikka iniciado com PID: {process.pid}")  
        time.sleep(1.5)  
        try:  
            hikka_process_obj = psutil.Process(process.pid)  
            if not hikka_process_obj.is_running() or hikka_process_obj.status() in [psutil.STATUS_ZOMBIE, psutil.STATUS_DEAD]:  
                logging.error(f"[INICIAR] Processo Hikka PID {process.pid} encerrou/zumbificou imediatamente. Status={hikka_process_obj.status()}.")  
                hikka_process_obj = None  
                return None  
            logging.info(f"[INICIAR] Verificando socket na porta {forced_port} para PID {process.pid}...")  
            if check_port_listening(forced_port, host='127.0.0.1', timeout=0.5):  
                logging.info(f"[INICIAR] Socket OK para localhost:{forced_port}.")  
            else:  
                logging.warning(f"[INICIAR] Socket falhou para localhost:{forced_port}. Hikka pode não estar vinculando a porta corretamente.")  
            logging.info(f"[INICIAR] Processo Hikka PID {process.pid} está rodando. Status={hikka_process_obj.status()}.")  
            return hikka_process_obj  
        except psutil.NoSuchProcess:  
            logging.error(f"[INICIAR] Processo Hikka PID {process.pid} desapareceu imediatamente.")  
            hikka_process_obj = None  
            return None  
    except Exception as e:  
        pid_str = str(process.pid) if process else "Desconhecido"  
        logging.exception(f"[INICIAR] Falha ao iniciar o processo Hikka (PID tentado: {pid_str}): {e}")  
        hikka_process_obj = None  
        return None  
  
def monitor_health(process_to_monitor):  
    """Monitora o processo Hikka e reinicia se necessário."""  
    global hikka_process_obj  
    if not process_to_monitor:  
        logging.error("[MONITOR] Processo inválido para monitoramento. Encerrando thread.")  
        return  
    restart_attempts = 0  
    last_successful_check = time.time() - HIKKA_RESTART_TIMEOUT - 1  
    logging.info(f"[MONITOR] Iniciando monitoramento de saúde para PID {process_to_monitor.pid}")  
    logging.info(f"[MONITOR] Aguardando {STARTUP_DELAY}s para inicialização...")  
    time.sleep(STARTUP_DELAY)  
    while not monitor_stop_event.is_set():  
        is_healthy = False  
        process_is_running = False  
        current_pid = "None"  
        try:  
            if process_to_monitor and process_to_monitor.is_running():  
                if process_to_monitor.status() != psutil.STATUS_ZOMBIE:  
                    process_is_running = True  
                    current_pid = process_to_monitor.pid  
                    logging.debug(f"[MONITOR] Processo {current_pid} rodando. Status={process_to_monitor.status()}")  
                else:  
                    logging.warning(f"[MONITOR] Processo {process_to_monitor.pid} é um zumbi.")  
                    process_to_monitor = None; hikka_process_obj = None; process_is_running = False  
            else:  
                if process_to_monitor:  
                    current_pid = process_to_monitor.pid  
                logging.debug(f"[MONITOR] Processo (PID: {current_pid}) não está rodando ou objeto inválido.")  
                process_to_monitor = None; hikka_process_obj = None; process_is_running = False  
        except psutil.NoSuchProcess:  
            logging.warning("[MONITOR] Processo Hikka monitorado desapareceu (NoSuchProcess).")  
            process_is_running = False; process_to_monitor = None; hikka_process_obj = None  
        except Exception as e:  
            logging.exception(f"[MONITOR] Erro inesperado ao verificar status (PID: {process_to_monitor.pid if process_to_monitor else 'None'}): {e}")  
            process_is_running = False  
  
        if process_is_running:  
            logging.debug(f"[MONITOR] Tentando verificação HTTP para PID {current_pid} em {HEALTH_CHECK_URL}")  
            try:  
                response = requests.get(HEALTH_CHECK_URL, timeout=5)  
                logging.debug(f"[MONITOR] Resposta: Status={response.status_code}")  
                response.raise_for_status()  
                logging.info(f"[MONITOR] Saúde OK (PID: {current_pid}) - Recebido {response.status_code} de {HEALTH_CHECK_URL}.")  
                is_healthy = True  
                last_successful_check = time.time()  
                restart_attempts = 0  
            except requests.exceptions.Timeout:  
                logging.warning(f"[MONITOR] Timeout na verificação para Hikka (PID: {current_pid}) em {HEALTH_CHECK_URL}.")  
            except requests.exceptions.ConnectionError:  
                logging.warning(f"[MONITOR] Conexão recusada para Hikka (PID: {current_pid}) em {HEALTH_CHECK_URL}.")  
            except requests.exceptions.RequestException as e:  
                status_code = getattr(e.response, 'status_code', 'N/A')  
                logging.warning(f"[MONITOR] Verificação falhou para Hikka (PID: {current_pid}) em {HEALTH_CHECK_URL}. Status={status_code}. Erro: {e}")  
            except Exception as e:  
                logging.exception(f"[MONITOR] Erro inesperado durante verificação (PID: {current_pid}) em {HEALTH_CHECK_URL}: {e}")  
        else:  
            is_healthy = False  
  
        if not is_healthy:  
            time_since_last_ok = time.time() - last_successful_check  
            if process_is_running or not process_to_monitor:  
                logging.warning(f"[MONITOR] Hikka insalubre ou morto (PID: {current_pid}). Último OK há {time_since_last_ok:.0f}s")  
            if time_since_last_ok > HIKKA_RESTART_TIMEOUT:  
                logging.error(f"[RESTART] Hikka insalubre/morto por mais de {HIKKA_RESTART_TIMEOUT}s. Reiniciando...")  
                if restart_attempts < MAX_RESTART_ATTEMPTS:  
                    restart_attempts += 1  
                    logging.info(f"[RESTART] Tentativa {restart_attempts}/{MAX_RESTART_ATTEMPTS}...")  
                    old_pid_to_log = current_pid  
                    if process_to_monitor:  
                        logging.warning(f"[RESTART] Tentando parar Hikka travada (PID: {old_pid_to_log})...")  
                        try:  
                            if process_to_monitor.is_running():  
                                process_to_monitor.terminate()  
                                process_to_monitor.wait(timeout=5)  
                        except (psutil.NoSuchProcess, psutil.TimeoutExpired):  
                            pass  
                        except Exception as e:  
                            logging.error(f"Erro ao terminar processo {old_pid_to_log}: {e}")  
                        try:  
                            proc_to_kill = psutil.Process(process_to_monitor.pid)  
                            if proc_to_kill.is_running():  
                                proc_to_kill.kill()  
                                logging.info(f"[RESTART] Processo Hikka {old_pid_to_log} forçado (kill).")  
                                proc_to_kill.wait(timeout=1)  
                        except psutil.NoSuchProcess:  
                            pass  
                        except Exception as e:  
                            logging.error(f"Erro no kill forçado: {e}")  
                    process_to_monitor = None; hikka_process_obj = None  
                    new_process = start_hikka_process(PORT)  
                    if new_process:  
                        process_to_monitor = new_process  
                        hikka_process_obj = new_process  
                        last_successful_check = time.time()  
                        restart_attempts = 0  
                        logging.info(f"[RESTART] Reinício bem-sucedido. Novo PID: {process_to_monitor.pid}.")  
                        time.sleep(STARTUP_DELAY)  
                    else:  
                        logging.error("[RESTART] Tentativa de reinício falhou. Tentando novamente.")  
                else:  
                    logging.critical(f"[MONITOR] Máximo de tentativas ({MAX_RESTART_ATTEMPTS}) atingido. Encerrando monitoramento.")  
                    monitor_stop_event.set()  
                    return  
        time.sleep(HEALTH_CHECK_INTERVAL)  
    logging.info("Monitoramento encerrado.")  
  
def handle_sigterm(signum, frame):  
    signal.signal(signal.SIGTERM, signal.SIG_IGN)  
    signal.signal(signal.SIGINT, signal.SIG_IGN)  
    logging.info(f"Recebido sinal {signum}. Iniciando desligamento...")  
    monitor_stop_event.set()  
    global hikka_process_obj  
    if hikka_process_obj:  
        pid_to_log = getattr(hikka_process_obj, 'pid', 'N/A')  
        try:  
            if hikka_process_obj.is_running():  
                logging.info(f"Tentando terminar Hikka (PID: {pid_to_log}) graciosamente...")  
                hikka_process_obj.terminate()  
                try:  
                    hikka_process_obj.wait(timeout=10)  
                    logging.info(f"Hikka (PID: {pid_to_log}) terminado.")  
                except psutil.TimeoutExpired:  
                    logging.warning(f"Hikka (PID: {pid_to_log}) não terminou em 10s. Forçando...")  
                    try:  
                        if hikka_process_obj.is_running():  
                            hikka_process_obj.kill()  
                        hikka_process_obj.wait(timeout=2)  
                    except psutil.NoSuchProcess:  
                        pass  
                    except Exception as kill_e:  
                        logging.error(f"Erro ao forçar término: {kill_e}")  
            else:  
                logging.info(f"Hikka (PID: {pid_to_log}) já estava parado.")  
        except psutil.NoSuchProcess:  
            logging.info(f"Hikka (PID: {pid_to_log}) não encontrado durante desligamento.")  
        except Exception as e:  
            logging.error(f"Erro ao parar Hikka (PID: {pid_to_log}): {e}")  
    logging.info("Aguardando encerramento de threads...")  
    time.sleep(1.0)  
    logging.info("Desligamento completo.")  
    sys.exit(0)  
  
signal.signal(signal.SIGTERM, handle_sigterm)  
signal.signal(signal.SIGINT, handle_sigterm)  
  
if __name__ == "__main__":  
    logging.info("keep_alive.py iniciado.")  
    hikka_process_obj = find_process_by_cmd(PYTHON_CMD)  
    if hikka_process_obj:  
        logging.info(f"Processo Hikka existente encontrado (PID: {hikka_process_obj.pid}).")  
        try:  
            if not isinstance(hikka_process_obj, psutil.Process):  
                hikka_process_obj = psutil.Process(hikka_process_obj.pid)  
            if not hikka_process_obj.is_running() or hikka_process_obj.status() == psutil.STATUS_ZOMBIE:  
                logging.warning(f"Hikka (PID: {hikka_process_obj.pid}) não está rodando. Reiniciando.")  
                hikka_process_obj = None  
        except psutil.NoSuchProcess:  
            logging.warning("Processo encontrado, mas desapareceu. Reiniciando.")  
            hikka_process_obj = None  
    if not hikka_process_obj:  
        logging.info("Nenhum Hikka ativo. Iniciando novo processo...")  
        hikka_process_obj = start_hikka_process(PORT)  
    if hikka_process_obj:  
        monitor_health(hikka_process_obj)  
    else:  
        logging.critical("Falha ao iniciar Hikka. Encerrando.")  
        sys.exit(1)  
EOF