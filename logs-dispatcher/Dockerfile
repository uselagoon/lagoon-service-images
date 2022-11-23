FROM fluent/fluentd:v1.15-1

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

USER root

COPY Gemfile Gemfile.lock /

RUN apk add --no-cache --update --virtual .build-deps \
      build-base ruby-dev ruby-bundler \
      && BUNDLE_FROZEN=true BUNDLE_SYSTEM=true bundle install \
      && gem list \
      && apk del .build-deps \
      && apk add --no-cache curl jq

COPY fluent.conf /fluentd/etc/
COPY entrypoint.sh /bin/

USER fluent

# environment variables that must be defined to point to the k8s api
# these are set by default when running in k8s
ENV KUBERNETES_SERVICE_HOST KUBERNETES_SERVICE_PORT
