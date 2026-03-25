.PHONY: build
build:
	docker build --platform linux/amd64 . -t lagoon/logs-concentrator:latest

.PHONY: test
test: build
	docker build --platform linux/amd64 ../logs-dispatcher -t lagoon/logs-dispatcher:latest
	cd .. && SKIP_BUILD=true bats test/logs-dispatcher-concentrator/logs-pipeline.bats

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
