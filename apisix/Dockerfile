FROM apache/apisix:3.14.1-debian

# Switch to root to install packages
USER root

# for envsubst
RUN apt-get update && apt-get install -y --no-install-recommends gettext-base \
    && rm -rf /var/lib/apt/lists/*

# config templates + entrypoint
COPY config-template.yaml /usr/local/apisix/conf/config-template.yaml
COPY config-dev-static.yaml /usr/local/apisix/conf/config-dev-static.yaml
COPY config-test-static.yaml /usr/local/apisix/conf/config-test-static.yaml
COPY entrypoint-simple.sh /docker-entrypoint-custom.sh

RUN chmod +x /docker-entrypoint-custom.sh && \
    chown apisix:apisix /usr/local/apisix/conf/config-*.yaml && \
    chown apisix:apisix /docker-entrypoint-custom.sh

# Drop back to the apisix user (same as upstream image)
USER apisix

ENTRYPOINT ["/docker-entrypoint-custom.sh"]