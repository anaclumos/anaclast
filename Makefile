DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR

PRODUCT := build/Build/Products/Release/Anaclast.app
INSTALLED := /Applications/Anaclast.app
AGENT := gui/$(shell id -u)/com.anaclumos.anaclast

.PHONY: generate build test install

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project Anaclast.xcodeproj -scheme Anaclast -configuration Release -derivedDataPath build -destination 'platform=macOS' -allowProvisioningUpdates -quiet build

test:
	swift test --package-path Core

install: build
	rsync -a --delete "$(PRODUCT)/" "$(INSTALLED)/"
	if launchctl print "$(AGENT)" >/dev/null 2>&1; then launchctl kickstart -k "$(AGENT)"; else if pgrep -x Anaclast >/dev/null; then pkill -x Anaclast; sleep 1; fi; open "$(INSTALLED)"; fi
