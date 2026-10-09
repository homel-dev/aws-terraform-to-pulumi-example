FROM python:3.12-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 10001 app \
    && useradd -u 10001 -g 10001 -M -s /usr/sbin/nologin app \
    && mkdir -p /opt/myorg/runtime \
    && chown -R 10001:10001 /opt/myorg

WORKDIR /opt/myorg
COPY --chown=10001:10001 app.py entrypoint.sh ./
RUN chmod 0555 entrypoint.sh app.py

USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]
