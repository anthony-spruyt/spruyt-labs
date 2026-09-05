# renovate: depName=golang datasource=docker
ARG GO_VERSION=1.26.8
FROM golang:${GO_VERSION}-alpine AS builder

ARG VERSION=dev
ARG COMMIT=unknown

WORKDIR /build
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
  -o /mcp-header-proxy .

FROM gcr.io/distroless/static:nonroot@sha256:1c2c046bc09ed40fad370b599a0b1ae7987f55b01e247cf27a7c27cd97e5bbc7
COPY --from=builder /mcp-header-proxy /mcp-header-proxy
USER 65534:65534
HEALTHCHECK NONE
ENTRYPOINT ["/mcp-header-proxy"]
