FROM golang:1.25.3-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /shutdown-orchestrator .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /shutdown-orchestrator /shutdown-orchestrator
USER 65534:65534
ENTRYPOINT ["/shutdown-orchestrator"]
