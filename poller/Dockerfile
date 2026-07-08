FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt
COPY poller.py .
RUN useradd --system --uid 10001 --home-dir /app poller
USER 10001
ENTRYPOINT ["python", "/app/poller.py"]
