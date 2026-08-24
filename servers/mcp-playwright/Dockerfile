# Playwright MCP server, serving MCP over Streamable HTTP.
#
# Upstream's own Dockerfile starts the server on stdio. This image passes
# --port/--host so it serves HTTP directly, matching source.transport "http".
FROM node:22-bookworm-slim@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436

# Browsers install outside /app so they stay readable after the USER switch.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

WORKDIR /app

RUN npm install @playwright/mcp@0.0.79 \
    && node_modules/.bin/playwright install-deps chromium \
    && node_modules/.bin/playwright install --no-shell chromium \
    && npm cache clean --force \
    && chmod -R a+rX /app "$PLAYWRIGHT_BROWSERS_PATH"

ENV PORT=8080

EXPOSE 8080

# Run non-root. The working directory must be writable: the server creates its
# default output directory (traces, screenshots) there.
USER node
WORKDIR /home/node

# --allowed-hosts '*' because the public hostname is assigned by the hosting
# platform at deploy time and is not known when this image is built.
CMD ["sh", "-c", "node /app/node_modules/@playwright/mcp/cli.js --headless --browser chromium --no-sandbox --port ${PORT} --host 0.0.0.0 --allowed-hosts '*' --ignore-https-errors --caps vision --isolated --viewport-size 1280x720"]
