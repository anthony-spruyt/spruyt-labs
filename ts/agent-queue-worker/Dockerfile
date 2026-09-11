FROM node:24-alpine@sha256:50c8e8ca1d27439048670df5883f32d57cf81cff6233222c893fd0d9884cbd81 AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit
COPY tsconfig.json ./
COPY src/ src/
RUN npx tsc

FROM node:24-alpine@sha256:50c8e8ca1d27439048670df5883f32d57cf81cff6233222c893fd0d9884cbd81
RUN apk add --no-cache tini
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit && npm cache clean --force
COPY --from=builder /app/dist/ dist/
HEALTHCHECK NONE
USER 1000:1000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/index.js"]
