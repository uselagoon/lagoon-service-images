FROM golang:1.22-alpine3.20 as builder

WORKDIR /build

COPY main.go .
COPY go.mod .
COPY go.sum .

# compile
RUN CGO_ENABLED=0  GOOS=linux GOARCH=amd64 go build docker-host .

FROM uselagoon/commons:latest as commons
FROM docker:27.0.3-dind

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

# Copy commons files
COPY --from=commons /lagoon /lagoon
COPY --from=commons /bin/fix-permissions /bin/ep /bin/docker-sleep /bin/
COPY --from=commons /sbin/tini /sbin/
COPY --from=commons /home /home

COPY --from=builder /build/docker-host /docker-host

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
