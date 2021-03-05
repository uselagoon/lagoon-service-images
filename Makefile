SHELL := /bin/bash
# amazee.io lagoon Makefile The main purpose of this Makefile is to provide easier handling of
# building images and running tests It understands the relation of the different images (like
# nginx-drupal is based on nginx) and builds them in the correct order Also it knows which
# services in docker-compose.yml are depending on which base images or maybe even other service
# images
#
# The main commands are:

# make build/<imagename>
# Builds an individual image and all of it's needed parents. Run `make build-list` to get a list of
# all buildable images. Make will keep track of each build image with creating an empty file with
# the name of the image in the folder `build`. If you want to force a rebuild of the image, either
# remove that file or run `make clean`

# make build
# builds all images in the correct order. Uses existing images for layer caching, define via `TAG`
# which branch should be used

# make tests/<testname>
# Runs individual tests. In a nutshell it does:
# 1. Builds all needed images for the test
# 2. Starts needed Lagoon services for the test via docker-compose up
# 3. Executes the test
#
# Run `make tests-list` to see a list of all tests.

# make tests
# Runs all tests together. Can be executed with `-j2` for two parallel running tests

# make up
# Starts all Lagoon Services at once, usefull for local development or just to start all of them.

# make logs
# Shows logs of Lagoon Services (aka docker-compose logs -f)

# make minishift
# Some tests need a full openshift running in order to test deployments and such. This can be
# started via openshift. It will:
# 1. Download minishift cli
# 2. Start an OpenShift Cluster
# 3. Configure OpenShift cluster to our needs

# make minishift/stop
# Removes an OpenShift Cluster

# make minishift/clean
# Removes all openshift related things: OpenShift itself and the minishift cli

#######
####### Default Variables
#######

# Parameter for all `docker build` commands, can be overwritten by passing `DOCKER_BUILD_PARAMS=` via the `-e` option
DOCKER_BUILD_PARAMS := --quiet

# On CI systems like jenkins we need a way to run multiple testings at the same time. We expect the
# CI systems to define an Environment variable CI_BUILD_TAG which uniquely identifies each build.
# If it's not set we assume that we are running local and just call it lagoon.
CI_BUILD_TAG ?= service-lagoon
# SOURCE_REPO is the repos where the upstream images are found (usually uselagoon, but can substiture for testlagoon)
UPSTREAM_REPO ?= uselagoon
UPSTREAM_TAG ?= latest

# Local environment
ARCH := $(shell uname | tr '[:upper:]' '[:lower:]')
LAGOON_VERSION := $(shell git describe --tags --exact-match 2>/dev/null || echo development)
DOCKER_DRIVER := $(shell docker info -f '{{.Driver}}')

# Name of the Branch we are currently in
BRANCH_NAME := $(shell git rev-parse --abbrev-ref HEAD)
SAFE_BRANCH_NAME := $(shell echo $(BRANCH_NAME) | sed -E 's:/:_:g')

# Init the file that is used to hold the image tag cross-reference table
$(shell >build.txt)
$(shell >scan.txt)

#######
####### Functions
#######

# Builds a docker image. Expects as arguments: name of the image, location of Dockerfile, path of
# Docker Build Context
docker_build = docker build $(DOCKER_BUILD_PARAMS) --build-arg LAGOON_VERSION=$(LAGOON_VERSION) --build-arg IMAGE_REPO=$(CI_BUILD_TAG) --build-arg UPSTREAM_REPO=$(UPSTREAM_REPO) --build-arg UPSTREAM_TAG=$(UPSTREAM_TAG) -t $(CI_BUILD_TAG)/$(1) -f $(2) $(3)

scan_image = docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v $(HOME)/Library/Caches:/root/.cache/ aquasec/trivy --timeout 5m0s $(CI_BUILD_TAG)/$(1) >> scan.txt

# Tags an image with the `testlagoon` repository and pushes it
docker_publish_testlagoon = docker tag $(CI_BUILD_TAG)/$(1) testlagoon/$(2) && docker push testlagoon/$(2) | cat

# Tags an image with the `uselagoon` repository and pushes it
docker_publish_uselagoon = docker tag $(CI_BUILD_TAG)/$(1) uselagoon/$(2) && docker push uselagoon/$(2) | cat


#######
####### Base Images
#######
####### Base Images are the base for all other images and are also published for clients to use during local development

images :=     oc \
							kubectl \
							oc-build-deploy-dind \
							kubectl-build-deploy-dind \
							rabbitmq \
							rabbitmq-cluster \
							athenapdf-service \
							curator \
							docker-host

# base-images is a variable that will be constantly filled with all base image there are
base-images += $(images)
s3-images += $(images)

# List with all images prefixed with `build/`. Which are the commands to actually build images
build-images = $(foreach image,$(images),build/$(image))

# Define the make recipe for all base images
$(build-images):
#	Generate variable image without the prefix `build/`
	$(eval image = $(subst build/,,$@))
# Call the docker build
	$(call docker_build,$(image),$(image)/Dockerfile,$(image))
#scan created image with Trivy
	$(call scan_image,$(image),)
# Touch an empty file which make itself is using to understand when the image has been last build
	touch $@

# Define dependencies of Base Images so that make can build them in the right order. There are two
# types of Dependencies
# 1. Parent Images, like `build/centos7-node6` is based on `build/centos7` and need to be rebuild
#    if the parent has been built
# 2. Dockerfiles of the Images itself, will cause make to rebuild the images if something has
#    changed on the Dockerfiles
build/rabbitmq: rabbitmq/Dockerfile
build/rabbitmq-cluster: build/rabbitmq rabbitmq-cluster/Dockerfile
build/docker-host: docker-host/Dockerfile
build/oc: oc/Dockerfile
build/kubectl: kubectl/Dockerfile
build/curator: curator/Dockerfile
build/oc-build-deploy-dind: build/oc oc-build-deploy-dind
build/athenapdf-service:athenapdf-service/Dockerfile
build/kubectl-build-deploy-dind: build/kubectl kubectl-build-deploy-dind


#######
####### Service Images
#######
####### Services Images are the Docker Images used to run the Lagoon Microservices, these images
####### will be expected by docker-compose to exist.



# Variables of service images we manage and build
services :=	logs-concentrator \
			logs-db-curator \
			logs-dispatcher \
			logs-tee

service-images += $(services)

build-services = $(foreach image,$(services),build/$(image))

# Recipe for all building service-images
$(build-services):
	$(eval image = $(subst build/,,$@))
	$(call docker_build,$(image),$(image)/Dockerfile,$(image))
	$(call scan_image,$(image),)
	touch $@

# Dependencies of Service Images
build/auth-server build/logs2email build/logs2slack build/logs2rocketchat build/logs2microsoftteams build/backup-handler build/controllerhandler build/webhook-handler build/webhooks2tasks build/api build/ui: build/yarn-workspace-builder
build/logs-concentrator: logs-concentrator/Dockerfile
build/logs-db-curator: build/curator
build/logs-dispatcher: logs-dispatcher/Dockerfile
build/logs-tee: logs-tee/Dockerfile

#######
####### Commands
#######
####### List of commands in our Makefile

# Builds all Images
.PHONY: build
build: $(foreach image,$(base-images) $(service-images) $(task-images),build/$(image))
# Outputs a list of all Images we manage
.PHONY: build-list
build-list:
	@for number in $(foreach image,$(build-images),build/$(image)); do \
			echo $$number ; \
	done

#######
####### Publishing Images
#######
####### All main&PR images are pushed to testlagoon repository
#######

# Publish command to testlagoon docker hub, done on any main branch or PR
publish-testlagoon-baseimages = $(foreach image,$(base-images),[publish-testlagoon-baseimages]-$(image))
# tag and push all images

.PHONY: publish-testlagoon-baseimages
publish-testlagoon-baseimages: $(publish-testlagoon-baseimages)

# tag and push of each image
.PHONY: $(publish-testlagoon-baseimages)
$(publish-testlagoon-baseimages):
#   Calling docker_publish for image, but remove the prefix '[publish-testlagoon-baseimages]-' first
		$(eval image = $(subst [publish-testlagoon-baseimages]-,,$@))
# 	Publish images with version tag
		$(call docker_publish_testlagoon,$(image),$(image):$(BRANCH_NAME))


# Publish command to amazeeio docker hub, this should probably only be done during a master deployments
publish-testlagoon-serviceimages = $(foreach image,$(service-images),[publish-testlagoon-serviceimages]-$(image))
# tag and push all images
.PHONY: publish-testlagoon-serviceimages
publish-testlagoon-serviceimages: $(publish-testlagoon-serviceimages)

# tag and push of each image
.PHONY: $(publish-testlagoon-serviceimages)
$(publish-testlagoon-serviceimages):
#   Calling docker_publish for image, but remove the prefix '[publish-testlagoon-serviceimages]-' first
		$(eval image = $(subst [publish-testlagoon-serviceimages]-,,$@))
# 	Publish images with version tag
		$(call docker_publish_testlagoon,$(image),$(image):$(BRANCH_NAME))


#######
####### All tagged releases are pushed to uselagoon repository with new semantic tags
#######

# Publish command to uselagoon docker hub, only done on tags
publish-uselagoon-baseimages = $(foreach image,$(base-images),[publish-uselagoon-baseimages]-$(image))

# tag and push all images
.PHONY: publish-uselagoon-baseimages
publish-uselagoon-baseimages: $(publish-uselagoon-baseimages)

# tag and push of each image
.PHONY: $(publish-uselagoon-baseimages)
$(publish-uselagoon-baseimages):
#   Calling docker_publish for image, but remove the prefix '[publish-uselagoon-baseimages]-' first
		$(eval image = $(subst [publish-uselagoon-baseimages]-,,$@))
# 	Publish images as :latest
		$(call docker_publish_uselagoon,$(image),$(image):latest)
# 	Publish images with version tag
		$(call docker_publish_uselagoon,$(image),$(image):$(LAGOON_VERSION))


# Publish command to amazeeio docker hub, this should probably only be done during a master deployments
publish-uselagoon-serviceimages = $(foreach image,$(service-images),[publish-uselagoon-serviceimages]-$(image))
# tag and push all images
.PHONY: publish-uselagoon-serviceimages
publish-uselagoon-serviceimages: $(publish-uselagoon-serviceimages)

# tag and push of each image
.PHONY: $(publish-uselagoon-serviceimages)
$(publish-uselagoon-serviceimages):
#   Calling docker_publish for image, but remove the prefix '[publish-uselagoon-serviceimages]-' first
		$(eval image = $(subst [publish-uselagoon-serviceimages]-,,$@))
# 	Publish images as :latest
		$(call docker_publish_uselagoon,$(image),$(image):latest)
# 	Publish images with version tag
		$(call docker_publish_uselagoon,$(image),$(image):$(LAGOON_VERSION))


# Clean all build touches, which will case make to rebuild the Docker Images (Layer caching is
# still active, so this is a very safe command)
clean:
	rm -rf build/*
