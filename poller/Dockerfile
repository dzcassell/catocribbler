FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt

RUN useradd --system --uid 10001 --home-dir /app poller
COPY poller.py /app/poller.py
RUN chown 10001:10001 /app/poller.py \
    && chmod 0555 /app/poller.py

USER 10001
ENTRYPOINT ["python", "/app/poller.py"]
