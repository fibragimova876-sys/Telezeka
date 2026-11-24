FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 CHAT_HOST=0.0.0.0 CHAT_PORT=8080 CHAT_DB=/data/chat.db
RUN groupadd -g 10001 telezeka && useradd -u 10001 -g 10001 -M telezeka && mkdir /data && chown 10001:10001 /data
WORKDIR /app
COPY server/server.py /app/server.py
USER 10001:10001
EXPOSE 8080
CMD ["python", "/app/server.py"]
