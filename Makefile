

.PHONY: dockerhost/tidy
dockerhost/tidy:
	cd docker-host && go mod tidy

.PHONY: dockerhost/test
dockerhost/test:
	cd docker-host && go test -v ./...

# Build the docker image
IMGTAG ?= latest
IMG=uselagoon/docker-host:${IMGTAG}
.PHONY: dockerhost/build
dockerhost/build: dockerhost/test
	docker build ./docker-host/. -t ${IMG}