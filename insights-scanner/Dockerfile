ARG UPSTREAM_REPO
ARG UPSTREAM_TAG
ARG GO_VER
FROM ${UPSTREAM_REPO:-uselagoon}/commons:${UPSTREAM_TAG:-latest} AS commons
FROM aquasec/trivy:0.63.0 AS trivy

FROM docker:28.4.0

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

ENV LAGOON=insights-scanner

# Copy commons files
COPY --from=commons /lagoon /lagoon
COPY --from=commons /bin/fix-permissions /bin/ep /bin/docker-sleep /bin/
COPY --from=commons /sbin/tini /sbin/
COPY --from=commons /home /home

RUN chmod g+w /etc/passwd \
    && mkdir -p /home

ENV TMPDIR=/tmp \
    TMP=/tmp \
    HOME=/home \
    # When Bash is invoked via `sh` it behaves like the old Bourne Shell and sources a file that is given in `ENV`
    ENV=/home/.bashrc \
    # When Bash is invoked as non-interactive (like `bash -c command`) it sources a file that is given in `BASH_ENV`
    BASH_ENV=/home/.bashrc

# Defining Versions
ENV KUBECTL_VERSION=v1.30.3

RUN apk add -U --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing aufs-util \
    && apk add --no-cache curl bash skopeo

RUN architecture=$(case $(uname -m) in x86_64 | amd64) echo "amd64" ;; aarch64 | arm64 | armv8) echo "arm64" ;; *) echo "amd64" ;; esac) \
    && curl -Lo /usr/bin/kubectl https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/${architecture}/kubectl \
    && chmod +x /usr/bin/kubectl

COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy

WORKDIR /app

COPY ./*.sh /app

RUN chmod +x /app/run.sh && /bin/fix-permissions /app/run.sh

# We'll set DOCKER_HOST to the lagoon default, but with the assumption that it's overridable at runtime by insights-handler
ENV DOCKER_HOST=docker-host.lagoon.svc

# bring in entrypoint to kill startup if the appropriate DOCLER_HOST isn't found
COPY ./dockerhost-entrypoint.sh /lagoon/entrypoints/100-docker-entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--", "/lagoon/entrypoints.sh"]
CMD ["/app/run.sh"]
