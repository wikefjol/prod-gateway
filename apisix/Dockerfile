FROM apache/apisix:3.14.1-debian

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

RUN chmod +x /docker-entrypoint-custom.sh && \
    chown apisix:apisix /usr/local/apisix/conf/config.yaml && \
    chown apisix:apisix /docker-entrypoint-custom.sh && \
    chown -R apisix:apisix /usr/local/apisix/lua

USER apisix
ENTRYPOINT ["/docker-entrypoint-custom.sh"]
