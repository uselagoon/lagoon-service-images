.PHONY: build
build:
	docker build --platform linux/amd64 . -t lagoon/logs-concentrator:latest

.PHONY: test
test:
	docker build --platform linux/amd64 . -t lagoon/logs-concentrator:test
	docker build --platform linux/amd64 ../logs-dispatcher -t lagoon/logs-dispatcher:test
	cd .. && SKIP_BUILD=true \
	  DISPATCHER_IMAGE=lagoon/logs-dispatcher:test \
	  CONCENTRATOR_IMAGE=lagoon/logs-concentrator:test \
	  bats test/logs-dispatcher-concentrator/logs-pipeline.bats

.PHONY: update-gemfile
update-gemfile:
	docker run --rm -it \
		--user=$$(id -u) \
		-v $$PWD/Gemfile:/tmp/Gemfile \
		-v $$PWD/Gemfile.lock:/tmp/Gemfile.lock \
		-w /tmp \
		--entrypoint bundle \
		fluent/fluentd:v1.18.0-1.3 \
		lock --update

.PHONY: bundle-outdated
bundle-outdated:
	docker run --rm -it \
		--user=$$(id -u) \
		-v $$PWD/Gemfile:/tmp/Gemfile \
		-v $$PWD/Gemfile.lock:/tmp/Gemfile.lock \
		-w /tmp \
		--entrypoint bundle \
		fluent/fluentd:v1.18.0-1.3 \
		outdated --only-explicit
