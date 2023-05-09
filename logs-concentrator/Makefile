.PHONY: build
build:
	docker build .

.PHONY: update-gemfile
update-gemfile:
	docker run --rm -it \
		--user=$$(id -u) \
		-v $$PWD/Gemfile:/tmp/Gemfile \
		-v $$PWD/Gemfile.lock:/tmp/Gemfile.lock \
		-w /tmp \
		--entrypoint bundle \
		fluent/fluentd:v1.16-1 \
		lock --update
