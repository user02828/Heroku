# Etapa de Build
FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Instala dependências para compilação
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc build-essential && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Clonando o repositório
RUN git clone https://github.com/user02828/Heroku /Hikka

# Criação de ambiente virtual
RUN python -m venv /Hikka/venv

# Atualiza o pip e instala dependências
RUN /Hikka/venv/bin/python -m pip install --upgrade pip && \
    /Hikka/venv/bin/pip install --no-cache-dir -r /Hikka/requirements.txt redis

# Etapa Final
FROM python:3.10-slim

# Instala pacotes necessários para execução
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 libavcodec-dev libavutil-dev libavformat-dev \
    libswscale-dev libavdevice-dev neofetch wkhtmltopdf gcc python3-dev net-tools && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Variáveis de ambiente para Render
ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Hikka/venv/bin:$PATH" \
    PYTHONPATH="/Hikka/venv/lib/python3.10/site-packages" \
    PORT=8080  # Render define a porta automaticamente, mas isso ajuda a evitar problemas

# Copia o app do estágio de build
COPY --from=builder /Hikka /Hikka

# Copia o entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /Hikka

# Expondo a porta (Render define automaticamente, mas é útil manter aqui)
EXPOSE 8080

# Definindo o EntryPoint
ENTRYPOINT ["/entrypoint.sh"]