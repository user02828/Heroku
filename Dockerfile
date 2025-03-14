FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Instala dependências para compilação
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc build-essential && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Clonando o repositório
RUN git clone https://github.com/user02828/Heroku /Hikka

# Criação do ambiente virtual
RUN python -m venv /Hikka/venv

# Atualiza o pip e instala as dependências
RUN /Hikka/venv/bin/python -m pip install --upgrade pip && \
    /Hikka/venv/bin/pip install --no-warn-script-location --no-cache-dir -r /Hikka/requirements.txt redis

FROM python:3.10-slim

# Instala pacotes necessários para execução
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 libavcodec-dev libavutil-dev libavformat-dev \
    libswscale-dev libavdevice-dev neofetch wkhtmltopdf gcc python3-dev && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* && apt-get clean

# Variáveis de ambiente para Render
ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Hikka/venv/bin:$PATH"

# Copia o app do estágio de build
COPY --from=builder /Hikka /Hikka

# Copia e torna executável o entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /Hikka

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]