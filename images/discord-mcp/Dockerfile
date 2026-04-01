# renovate: depName=saseq/discord-mcp datasource=docker
FROM saseq/discord-mcp:1.5.1 AS mcp-server

FROM node:22-alpine

# Install Java runtime (discord-mcp is a Spring Boot Java app)
RUN apk add --no-cache openjdk17-jre-headless

# renovate: depName=supergateway datasource=npm
ARG SUPERGATEWAY_VERSION=0.2.2
RUN npm install -g supergateway@${SUPERGATEWAY_VERSION}

# Copy the MCP server jar from the discord-mcp image
COPY --from=mcp-server /app/app.jar /app/app.jar

USER 1000

# Supergateway wraps the stdio MCP server and exposes it as Streamable HTTP
# Default port 8080, health endpoint at /healthz, MCP endpoint at /mcp
EXPOSE 8080

ENTRYPOINT ["supergateway", \
  "--stdio", "java -jar /app/app.jar", \
  "--outputTransport", "streamableHttp", \
  "--port", "8080", \
  "--healthEndpoint", "/healthz"]
