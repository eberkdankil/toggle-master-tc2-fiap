FROM python:3.9-slim AS builder

WORKDIR /app

COPY requirements.txt .

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir -r requirements.txt

# --- Imagem final ---
FROM python:3.9-slim

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

EXPOSE 8002

CMD ["gunicorn", "--bind", "0.0.0.0:8002", "--workers", "4", "--threads", "2", "--timeout", "120", "app:app"]