SHELL := /bin/bash
.DEFAULT_GOAL := build
.NOTPARALLEL:

PROJECT_DIR := $(CURDIR)
PYTHON ?= python3
INSTALL_DIR ?= $(HOME)/Applications
RUNTIME_DIR := $(HOME)/Library/Application Support/wisprM/runtime
BUILD_APP := $(PROJECT_DIR)/dist/wisprM.app
INSTALLED_APP := $(INSTALL_DIR)/wisprM.app

.PHONY: all help check-python build test swift-test python-test verify install run open setup-runtime clean

all: build

help:
	@printf '%s\n' \
	  'make                 Build and sign dist/wisprM.app' \
	  'make test            Run Swift and Python regression tests' \
	  'make verify          Check the existing bundle and worker startup' \
	  'make install         Build and install in ~/Applications' \
	  'make open            Open the installed app' \
	  'make run             Build and open dist/wisprM.app' \
	  'make setup-runtime   Install the separate, hash-locked MLX runtime' \
	  'make clean           Remove only .build/ and dist/' \
	  '' \
	  'Overrides: PYTHON=/path/to/python3.12 INSTALL_DIR=/custom/Applications'

check-python:
	@"$(PYTHON)" -c 'import sys; sys.exit(0 if sys.version_info[:2] in ((3,12),(3,13)) else "wisprM requires Python 3.12 or 3.13. Set PYTHON=/path/to/python3.12.")'

build: check-python
	@PYTHON="$(PYTHON)" bash "$(PROJECT_DIR)/scripts/build.sh"

test: swift-test python-test

swift-test: check-python
	xcrun swift test --package-path "$(PROJECT_DIR)"

python-test: check-python
	"$(PYTHON)" -m unittest discover -s "$(PROJECT_DIR)/Tests" -p 'test_*.py'

verify: check-python
	@test -d "$(BUILD_APP)" || { printf '%s\n' 'Build app not found. Run make build first.' >&2; exit 1; }
	"$(PYTHON)" "$(PROJECT_DIR)/scripts/check-bundle.py" "$(BUILD_APP)"

install: build
	"$(PYTHON)" "$(PROJECT_DIR)/scripts/local-app.py" install --source "$(BUILD_APP)" --destination "$(INSTALL_DIR)"

run: build
	open "$(BUILD_APP)"

open:
	@test -d "$(INSTALLED_APP)" || { printf '%s\n' 'Installed app not found. Run make install first.' >&2; exit 1; }
	open "$(INSTALLED_APP)"

setup-runtime: check-python
	bash "$(PROJECT_DIR)/runtime/setup-runtime.sh" "$(RUNTIME_DIR)" "$(PYTHON)"

clean: check-python
	"$(PYTHON)" "$(PROJECT_DIR)/scripts/local-app.py" clean
