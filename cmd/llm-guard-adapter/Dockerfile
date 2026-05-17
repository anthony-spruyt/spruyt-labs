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

FROM gcr.io/distroless/static:nonroot@sha256:963fa6c544fe5ce420f1f54fb88b6fb01479f054c8056d0f74cc2c6000df5240
COPY --from=builder /llm-guard-adapter /llm-guard-adapter
USER 65534:65534
HEALTHCHECK NONE
ENTRYPOINT ["/llm-guard-adapter"]
