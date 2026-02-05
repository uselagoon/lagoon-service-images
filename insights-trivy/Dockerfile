FROM aquasec/trivy:0.69.1

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

ENV LAGOON=insights-scanner

ENV TRIVY_CACHE_DIR=/

RUN  trivy image --cache-dir . --download-db-only && \
     trivy image --cache-dir . --download-java-db-only