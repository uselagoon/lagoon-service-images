FROM alpine:3.22.1

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

COPY mariadb-client-10.11.6-apk/ mongodb-tools-4.2.14-apk/ /tmp/

RUN architecture=$(case $(uname -m) in x86_64 | amd64) echo "amd64" ;; aarch64 | arm64 | armv8) echo "arm64" ;; *) echo "amd64" ;; esac) \
	&& apk add --allow-untrusted --no-cache \
        /tmp/$architecture-mariadb-client-10.11.6-r0.apk \
        /tmp/$architecture-mariadb-common-10.11.6-r0.apk \
        /tmp/$architecture-mongodb-tools-4.2.14-r17.apk \
	&& rm -rf /tmp/* \
	&& apk add --no-cache bash \
		grep \
		mariadb-connector-c \
		postgresql-client \
		sed \
	&& rm -rf /var/cache/apk/*
