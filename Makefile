SHELL := /bin/bash
PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: all build check test lint integration-docker install uninstall clean

all: build

## Regenerate dist/ayneh.sh from lib/*.sh
build:
	./build.sh

## Fail if dist/ayneh.sh is stale (used by CI)
check:
	./build.sh --check

## Offline smoke tests (no network required)
test: check
	bash tests/smoke.sh

## Slow end-to-end Docker mirror test (needs privileged Docker)
integration-docker:
	bash tests/docker-dind.sh

## Static analysis; install shellcheck first
lint:
	shellcheck -x lib/*.sh ayneh build.sh install.sh tests/smoke.sh scan.sh

## Install the single-file build as `ayneh`
install: build
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 0755 dist/ayneh.sh "$(DESTDIR)$(PREFIX)/bin/ayneh"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/ayneh"

clean:
	rm -rf dist
