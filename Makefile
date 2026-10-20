# SparkPlug — build, run and test. Needs Xcode 26+ and xcodegen (`brew install xcodegen`).
#
#   make run            build and open the app
#   make demo           open it with the sample week (your calendars and tasks are not touched)
#   make test           the core package's tests, then the app's (which build the app)
#   make open           generate the Xcode project and open it
#   TEAM=ABCDE12345     sign with your own Apple developer team instead of ad-hoc signing

CONFIG     ?= Debug
TEAM       ?=
DERIVED    := build
APP        := $(DERIVED)/Build/Products/$(CONFIG)/SparkPlug.app
SIGNING    := $(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM) CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development",)

.PHONY: project build run demo test core-test app-test open icon clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project SparkPlug.xcodeproj -scheme SparkPlug -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' $(SIGNING) build -quiet

run: build
	open $(APP)

demo: build
	open -n $(APP) --args --demo

core-test:
	swift test --package-path Core

app-test: project
	xcodebuild -project SparkPlug.xcodeproj -scheme SparkPlug -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' $(SIGNING) test -quiet

test: core-test app-test

open: project
	open SparkPlug.xcodeproj

icon:
	swift scripts/make-icon.swift

clean:
	rm -rf $(DERIVED) SparkPlug.xcodeproj Core/.build
