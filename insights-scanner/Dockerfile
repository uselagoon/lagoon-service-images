ARG UPSTREAM_REPO
ARG UPSTREAM_TAG
ARG GO_VER
FROM ${UPSTREAM_REPO:-uselagoon}/commons:${UPSTREAM_TAG:-latest} as commons

FROM docker:20.10.24

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-images" repository="https://github.com/uselagoon/lagoon-images"

ENV LAGOON=build-deploy-image


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
ENV KUBECTL_VERSION=v1.27.6 \
    HELM_VERSION=v3.13.0 \
    HELM_SHA256=138676351483e61d12dfade70da6c03d471bbdcac84eaadeb5e1d06fa114a24f

RUN apk add -U --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing aufs-util \
    && apk upgrade --no-cache openssh openssh-keygen openssh-client-common openssh-client-default \
    && apk add --no-cache openssl curl jq parallel bash git py-pip skopeo \
    && git config --global user.email "lagoon@lagoon.io" && git config --global user.name lagoon \
    && pip install shyaml yq \
    && curl -Lo /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x /usr/bin/kubectl \
    && curl -Lo /usr/bin/yq3 https://github.com/mikefarah/yq/releases/download/3.3.2/yq_linux_amd64 \
    && chmod +x /usr/bin/yq3 \
    && curl -Lo /usr/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_linux_amd64 \
    && chmod +x /usr/bin/yq \
    && curl -Lo /tmp/helm.tar.gz https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
    && echo "${HELM_SHA256}  /tmp/helm.tar.gz" | sha256sum -c -  \
    && mkdir /tmp/helm \
    && tar -xzf /tmp/helm.tar.gz -C /tmp/helm --strip-components=1 \
    && mv /tmp/helm/helm /usr/bin/helm \
    && chmod +x /usr/bin/helm \
    && rm -rf /tmp/helm*

RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.52.2


WORKDIR /app

COPY ./*.sh /app

RUN chmod +x /app/run.sh && /bin/fix-permissions /app/run.sh

ENTRYPOINT ["/sbin/tini", "--", "/lagoon/entrypoints.sh"]
CMD ["/app/run.sh"]