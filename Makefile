SHELL := /bin/bash
.DEFAULT_GOAL := build
.NOTPARALLEL:

MOBILE_DIR := mobile
DESKTOP_TARGETS := all build verify install run open setup-runtime clean swift-test python-test check-python

.PHONY: help desktop desktop-build mobile mobile-build mobile-device mobile-project desktop-test mobile-test test $(DESKTOP_TARGETS)

$(DESKTOP_TARGETS):
	$(MAKE) -C desktop $@

desktop desktop-build: build

mobile mobile-build:
	$(MAKE) -C $(MOBILE_DIR) build

mobile-device:
	$(MAKE) -C $(MOBILE_DIR) device

mobile-project:
	$(MAKE) -C $(MOBILE_DIR) project

desktop-test:
	$(MAKE) -C desktop test

mobile-test:
	$(MAKE) -C $(MOBILE_DIR) test

test: desktop-test mobile-test

help:
	@printf '%s\n' \
		'make / make desktop       Build the macOS app in desktop/dist/' \
		'make mobile               Build the iOS Simulator app' \
		'make mobile-device        Build the unsigned iPhone Release app' \
		'make mobile-project       Generate the Xcode project using local signing' \
		'make test                 Run both apps Swift and Python tests' \
		'make desktop-test         Run desktop/shared-core tests' \
		'make mobile-test          Run mobile tests' \
		'make install / make open  Install/open the macOS app' \
		'make help                 Show these shortcuts' \
		'' \
		'Use make -C desktop help or make -C $(MOBILE_DIR) for app-specific commands.'
