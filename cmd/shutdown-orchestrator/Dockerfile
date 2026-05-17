# renovate: depName=golang datasource=docker
ARG GO_VERSION=1.26.3
FROM golang:${GO_VERSION}-alpine AS builder

ARG VERSION=dev
ARG COMMIT=unknown

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
  -o /shutdown-orchestrator .

FROM gcr.io/distroless/static:nonroot@sha256:963fa6c544fe5ce420f1f54fb88b6fb01479f054c8056d0f74cc2c6000df5240
COPY --from=builder /shutdown-orchestrator /shutdown-orchestrator
USER 65534:65534
# Health monitored via Kubernetes liveness/readiness probes, not docker healthcheck.
HEALTHCHECK NONE
ENTRYPOINT ["/shutdown-orchestrator"]
