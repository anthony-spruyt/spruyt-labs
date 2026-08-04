FROM node:24-alpine@sha256:d32cdf619f63fe0471182d08996dd516c6275bb5fd31ae06e55a570bd9e1ad43 AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit
COPY tsconfig.json ./
COPY src/ src/
RUN npx tsc

FROM node:24-alpine@sha256:d32cdf619f63fe0471182d08996dd516c6275bb5fd31ae06e55a570bd9e1ad43
RUN apk add --no-cache tini
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit && npm cache clean --force
COPY --from=builder /app/dist/ dist/
HEALTHCHECK NONE
USER 1000:1000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/index.js"]
