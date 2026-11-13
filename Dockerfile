FROM node:24-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY web.zip /tmp/web.zip

RUN mkdir -p /tmp/web \
    && unzip -q /tmp/web.zip -d /tmp/web \
    && git clone https://github.com/titaniumnetwork-dev/Ultraviolet-App /app/web-browser \
    && cd /app/web-browser \
    && git checkout a1762248768730d06ffa5a652345aeef7126ab63 \
    && npm install --omit=dev --no-audit --no-fund --engine-strict=false \
    && cp /tmp/web/web-browser-setup/web-browser-setup/browser.html /app/web-browser/public/index.html \
    && rm -rf /tmp/web /tmp/web.zip

WORKDIR /app/web-browser

ENV NODE_ENV=production

CMD ["sh", "-c", "PORT=${PORT:-8080} node src/index.js"]
