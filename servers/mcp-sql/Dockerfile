# Data API Builder (DAB) exposed over MCP.
#
# DAB's runtime configuration (dab-config.json) is provisioned into the
# container at deployment time. To ensure a clean, deterministic startup, this
# image waits for that configuration to be in place before launching DAB
# (see entrypoint.sh) rather than starting against a placeholder.
FROM mcr.microsoft.com/azure-databases/data-api-builder:2.0.9@sha256:ad5ac1793049f95fdd4210ca50d3c913855553139b64992046a071cd63eeead0

# Remove the image's placeholder default config so DAB starts only against the
# deployment-provided configuration.
RUN rm -f /App/dab-config.json

# Readiness-poll settings (overridable at runtime). POLL_INTERVAL is sub-second
# so DAB starts as soon as the configuration is available.
ENV CONFIG_PATH=/App/dab-config.json \
    POLL_INTERVAL=0.2 \
    TIMEOUT=300

COPY entrypoint.sh /App/entrypoint.sh
RUN chmod +x /App/entrypoint.sh

EXPOSE 5000

# Run as the non-root 'app' user (uid 1654) that the base image already
# provides, rather than root. /App and its assemblies are world-readable, so no
# ownership change is needed; the mounted dab-config.json is read-only at runtime.
USER app

ENTRYPOINT ["/App/entrypoint.sh"]
