FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir -r requirements.txt

# --- Imagem final ---
FROM python:3.12-slim

# Usuário sem privilégios
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

# Copia venv do builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app

COPY app.py .
# COPY . .  # descomente se tiver mais arquivos

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8005

# opentelemetry-instrument faz auto-instrumentação (Flask/botocore) sem
# mexer no código do app — lê config via env vars (OTEL_SERVICE_NAME,
# OTEL_EXPORTER_OTLP_ENDPOINT, ver gitops/02-configmap.yaml e 07-analytics-service.yaml).
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8005", "--workers", "4", "--threads", "2", "--timeout", "120", "app:app"]