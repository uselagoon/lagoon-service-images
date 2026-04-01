.PHONY: build
build:
	docker build . -t lagoon/insights-scanner:latest

.PHONY: test
test:
	docker build . -t lagoon/insights-scanner:test
	cd .. && SKIP_BUILD=true \
	  SCANNER_IMAGE=lagoon/insights-scanner:test \
	  bats test/insights-scanner/insights-scanner.bats
