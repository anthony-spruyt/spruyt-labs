# renovate: depName=golang datasource=docker
ARG GO_VERSION=1.26.4
FROM golang:${GO_VERSION}-alpine AS builder

ARG VERSION=dev
ARG COMMIT=unknown

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
  -o /kata-tap-qdisc-fix .

FROM gcr.io/distroless/static:nonroot@sha256:f7f8f729987ad0fdf6b05eeeae94b26e6a0f613bdf46feea7fc40f7bd72953e6
COPY --from=builder /kata-tap-qdisc-fix /kata-tap-qdisc-fix
USER 65534:65534
# Health monitored via Kubernetes liveness/readiness probes, not docker healthcheck.
HEALTHCHECK NONE
ENTRYPOINT ["/kata-tap-qdisc-fix"]
