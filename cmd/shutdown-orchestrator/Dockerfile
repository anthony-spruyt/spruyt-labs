# NOTE: go.mod requires Go 1.25.3 but golang:1.25-alpine does not exist yet.
# Using golang:1.24-alpine as the closest available image.
# Update to golang:1.25-alpine when Docker Hub publishes it.
FROM golang:1.24-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /shutdown-orchestrator .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /shutdown-orchestrator /shutdown-orchestrator
USER 65534:65534
ENTRYPOINT ["/shutdown-orchestrator"]
