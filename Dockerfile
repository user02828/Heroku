FROM python:3.10-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc build-essential net-tools curl libcairo2 ffmpeg libmagic1 neofetch \
    wkhtmltopdf && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*
    
RUN git clone https://github.com/user02828/Heroku /Heroku

RUN python -m venv /Heroku/venv

RUN /Heroku/venv/bin/python -m pip install --upgrade pip
RUN /Heroku/venv/bin/pip install --no-cache-dir -r /Heroku/requirements.txt redis flask requests

FROM python:3.10-slim

ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Hikka/venv/bin:$PATH"

COPY --from=builder /Heroku /Heroku 
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /Hikka

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]