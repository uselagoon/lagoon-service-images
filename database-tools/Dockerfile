FROM alpine:3.23.3

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.17/community' >> /etc/apk/repositories \
	&& apk update \
	&& apk add --no-cache bash \
	grep \
	sed \
	mongodb-tools=4.2.14-r17 \
	mysql-client=10.11.6-r0 \
	postgresql-client \
	&& rm -rf /var/cache/apk/*
