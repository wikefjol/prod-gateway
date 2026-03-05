FROM python:3.11-slim

WORKDIR /docs

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY mkdocs.yml .
COPY docs/ ./docs/
COPY overrides/ ./overrides/

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/docs/ || exit 1

CMD ["mkdocs", "serve", "--dev-addr", "0.0.0.0:8000"]
