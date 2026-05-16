# renovate: depName=golang datasource=docker
ARG GO_VERSION=1.26.3
FROM golang:${GO_VERSION}-alpine AS builder

ARG VERSION=dev
ARG COMMIT=unknown

WORKDIR /build
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
  -o /llm-guard-adapter .

FROM gcr.io/distroless/static:nonroot@sha256:e3f945647ffb95b5839c07038d64f9811adf17308b9121d8a2b87b6a22a80a39
COPY --from=builder /llm-guard-adapter /llm-guard-adapter
USER 65534:65534
HEALTHCHECK NONE
ENTRYPOINT ["/llm-guard-adapter"]
