.PHONY: test
test:
		@scripts/run-bats.sh

SHELLCHECK ?= docker run --rm -v $(shell pwd):/mnt koalaman/shellcheck:v0.5.0
.PHONY: lint
lint:
		$(SHELLCHECK) assets/*
