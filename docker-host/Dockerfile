FROM uselagoon/commons:latest as commons

FROM docker:28.2.1-dind

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

# Copy commons files
COPY --from=commons /lagoon /lagoon
COPY --from=commons /bin/fix-permissions /bin/ep /bin/docker-sleep /bin/
COPY --from=commons /sbin/tini /sbin/
COPY --from=commons /home /home

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
    REPOSITORY_TO_UPDATE=amazeeio \
    BIP=172.16.0.1/16 \
    REGISTRY_MIRROR=https://imagecache.amazeeio.cloud

RUN fix-permissions /home

COPY update-push-images.sh /update-push-images.sh
COPY update-images.sh /update-images.sh
COPY prune-images.sh /prune-images.sh
COPY remove-exited.sh /remove-exited.sh

ENTRYPOINT ["/sbin/tini", "--", "/lagoon/entrypoints.sh"]

CMD ["sh", "-c", "sh /usr/local/bin/dind /usr/local/bin/dockerd --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --insecure-registry=${REGISTRY} --insecure-registry=harbor-harbor-core.harbor.svc.cluster.local:80 --bip=${BIP} --storage-driver=overlay2 --registry-mirror=${REGISTRY_MIRROR}"]
