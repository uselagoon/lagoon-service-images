FROM alpine:3.22.1

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.17/community' >> /etc/apk/repositories \
	&& echo 'http://dl-cdn.alpinelinux.org/alpine/v3.17/main' >> /etc/apk/repositories \
	&& apk update \
	&& apk add --no-cache bash \
		grep \
		sed \
		mariadb-client=10.6.16-r0 \
		mariadb-common=10.6.16-r0 \
		mariadb-connector-c \
		mongodb-tools=4.2.14-r17 \
		mysql-client=10.6.16-r0 \
		postgresql-client \
	&& rm -rf /var/cache/apk/*
