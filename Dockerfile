# Etapa de build
FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Instalação de dependências necessárias para a compilação
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc build-essential && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Clonando repositório e criando ambiente virtual
WORKDIR /Hikka
RUN git clone https://github.com/user02828/Heroku.git . && \
    python -m venv venv && \
    venv/bin/python -m pip install --upgrade pip && \
    venv/bin/pip install --no-warn-script-location --no-cache-dir -r requirements.txt redis

# Etapa final - runtime
FROM python:3.10-slim

# Instalação das dependências necessárias
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 libavcodec-dev libavutil-dev libavformat-dev \
    libswscale-dev libavdevice-dev neofetch wkhtmltopdf gcc python3-dev && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* && apt-get clean

# Definição de variáveis de ambiente
ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Hikka/venv/bin:$PATH"

# Copiando a aplicação
COPY --from=builder /Hikka /Hikka
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /Hikka

# Expondo portas usadas pelo aplicativo
EXPOSE 8080 8081

# Definição do ponto de entrada
ENTRYPOINT ["/entrypoint.sh"]