FROM golang:1.22-alpine3.20 AS builder
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Copy the go source
COPY cmd/main.go cmd/main.go
COPY internal/ internal/

# compile
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} go build -o docker-host cmd/main.go

FROM uselagoon/commons:latest AS commons
FROM docker:27.0.3-dind

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

# Copy commons files
COPY --from=commons /lagoon /lagoon
COPY --from=commons /bin/fix-permissions /bin/ep /bin/docker-sleep /bin/
COPY --from=commons /sbin/tini /sbin/
COPY --from=commons /home /home

COPY --from=builder /workspace/docker-host /docker-host

ENV TMPDIR=/tmp \
    TMP=/tmp \
    HOME=/home \
    # When Bash is invoked via `sh` it behaves like the old Bourne Shell and sources a file that is given in `ENV`
    ENV=/home/.bashrc \
    # When Bash is invoked as non-interactive (like `bash -c command`) it sources a file that is given in `BASH_ENV`
    BASH_ENV=/home/.bashrc

RUN apk add --no-cache bash

ENV DOCKER_HOST=docker-host \
    REGISTRY=docker-registry.default.svc:5000 \
    REPOSITORIES_TO_UPDATE=*uselagoon/*:* \
    BIP=172.16.0.1/16 \
    REGISTRY_MIRROR=https://imagecache.amazeeio.cloud

RUN fix-permissions /home

ENTRYPOINT ["/sbin/tini", "--", "/lagoon/entrypoints.sh"]

CMD ["sh", "-c", "/docker-host"]
