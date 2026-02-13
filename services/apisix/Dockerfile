FROM apache/apisix:3.15.0-debian

ARG GIT_SHA=unknown
LABEL org.opencontainers.image.revision=$GIT_SHA
LABEL project=apisix-gateway

# Switch to root to install packages
USER root

# for network debugging (optional but useful)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    dnsutils \
    iputils-ping \
    telnet \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Copy single source-of-truth config + entrypoint
COPY config.yaml /usr/local/apisix/conf/config.yaml
COPY entrypoint-simple.sh /docker-entrypoint-custom.sh

# Copy custom Lua modules
COPY lua /usr/local/apisix/lua

RUN mkdir -p /usr/local/apisix/logs/billing && \
    chmod +x /docker-entrypoint-custom.sh && \
    chown apisix:apisix /usr/local/apisix/conf/config.yaml && \
    chown apisix:apisix /docker-entrypoint-custom.sh && \
    chown -R apisix:apisix /usr/local/apisix/lua && \
    chown -R apisix:apisix /usr/local/apisix/logs/billing

USER root
ENTRYPOINT ["/docker-entrypoint-custom.sh"]
