SHELL := /bin/bash
.DEFAULT_GOAL := build
.NOTPARALLEL:
DEVICE ?= iPhone 17 Pro
SIMULATOR_ID ?=
TEAM ?=
.PHONY: project resolve build device test run clean
project:
	WISPRM_DEVELOPMENT_TEAM="$(TEAM)" python3 scripts/generate-project.py
resolve: project
	xcodebuild -resolvePackageDependencies -project wisprM.xcodeproj -scheme wisprM -clonedSourcePackagesDirPath .build/Packages
build: project
	python3 scripts/build.py simulator
device: project
	python3 scripts/build.py device
test:
	xcrun swift test --package-path MobileCore
	python3 -m unittest discover -s Tests -p 'test_*.py'
run: build
	python3 scripts/simulator.py --simulator "$(SIMULATOR_ID)" --name "$(DEVICE)"
clean:
	rm -rf .build
