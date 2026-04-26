FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY tsconfig.json ./
COPY src/ src/
RUN npx tsc

FROM node:22-alpine
RUN apk add --no-cache tini
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY --from=builder /app/dist/ dist/
HEALTHCHECK NONE
USER 1000:1000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/index.js"]
