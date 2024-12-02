FROM uselagoon/nginx:latest

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-service-images" repository="https://github.com/uselagoon/lagoon-service-images"

COPY --chmod=664 nginx.conf /etc/nginx/conf.d/app.conf
COPY web/ /app/
