# ==========================================
# STAGE 1: Dependency Builder
# ==========================================
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Build Python wheels
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip wheel --no-cache-dir --wheel-dir=/build/wheels -r requirements.txt

# ==========================================
# STAGE 2: Lightweight Production Runtime
# ==========================================
FROM python:3.11-slim AS runner

WORKDIR /app

# Install runtime curl for container health check
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-privileged system user for hardened security
RUN addgroup --system --gid 1001 naviagroup && \
    adduser --system --uid 1001 --gid 1001 naviauser

# Install pre-built wheels from builder stage
COPY --from=builder /build/wheels /wheels
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && \
    rm -rf /wheels requirements.txt

# Copy backend application source
COPY --chown=naviauser:naviagroup backend/app /app/app

# Switch to non-root user
USER naviauser

# Expose FastAPI listening port
EXPOSE 8000

# Container liveness health check
HEALTHCHECK --interval=20s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Launch production ASGI server (respects PORT and WORKERS env variables)
ENV PORT=8000 \
    WORKERS=2

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --workers ${WORKERS}"]
