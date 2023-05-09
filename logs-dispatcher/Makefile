.PHONY: build
build:
	docker build .

.PHONY: update-gemfile
update-gemfile:
	docker run --rm -it \
		--user=$$(id -u) \
		-v $$PWD/vendor:/tmp/vendor \
		-v $$PWD/Gemfile:/tmp/Gemfile \
		-v $$PWD/Gemfile.lock:/tmp/Gemfile.lock \
		-w /tmp \
		--entrypoint bundle \
		fluent/fluentd:v1.16-1 \
		lock --update

.PHONY: update-vendor-cache
update-vendor-cache:
	docker run --rm -it \
		--user=$$(id -u) \
		-v $$PWD/vendor:/tmp/vendor \
		-v $$PWD/Gemfile:/tmp/Gemfile \
		-v $$PWD/Gemfile.lock:/tmp/Gemfile.lock \
		-w /tmp \
		-e BUNDLE_NO_INSTALL=true \
		--entrypoint bundle \
		fluent/fluentd:v1.16-1 \
		cache
