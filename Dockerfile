# Etapa de Build
FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Instala dependências para compilação
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc build-essential && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Clonando o repositório (utilizando o GitHub informado)
RUN git clone https://github.com/user02828/Heroku /Hikka

# Criação de ambiente virtual
RUN python -m venv /Hikka/venv

# Atualiza o pip e instala dependências
RUN /Hikka/venv/bin/python -m pip install --upgrade pip && \
    /Hikka/venv/bin/pip install --no-cache-dir -r /Hikka/requirements.txt redis flask requests

# Etapa Final
FROM python:3.10-slim

# Instala pacotes necessários para execução e limpa o cache
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 libavcodec-dev libavutil-dev libavformat-dev \
    libswscale-dev libavdevice-dev neofetch wkhtmltopdf gcc python3-dev net-tools && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* && \
    update-alternatives --remove-all lzma || true

# Definição de variáveis de ambiente
ENV DOCKER=true
ENV GIT_PYTHON_REFRESH=quiet
ENV PIP_NO_CACHE_DIR=1
ENV PATH="/Hikka/venv/bin:$PATH"
ENV PYTHONPATH="/Hikka/venv/lib/python3.10/site-packages"
ENV PORT=8080
ENV HIKKA_RESTART_TIMEOUT=60
ENV FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Copia o app do estágio de build
COPY --from=builder /Hikka /Hikka

# Copia o entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /Hikka

# Expondo a porta (Render define automaticamente, mas é útil manter aqui)
EXPOSE 8080

# Definindo o ENTRYPOINT
ENTRYPOINT ["/entrypoint.sh"]