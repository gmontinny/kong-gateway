ARG KONG_BASE=kong:latest
FROM ${KONG_BASE}

ARG PROFILE=dev
COPY config/kong.${PROFILE}.yaml /etc/kong/kong.yaml

HEALTHCHECK --interval=60s --timeout=10s --retries=10 CMD kong-health

USER kong
