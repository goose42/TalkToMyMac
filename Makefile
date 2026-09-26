.PHONY: all build clean run test setup-signing

APP_BUNDLE = build/TalkToMyMac.app
SWIFT_BUILD_DIR = .build/release
SWIFT_BINARY = $(SWIFT_BUILD_DIR)/TalkToMyMac
CODESIGN_IDENTIFIER = com.talktomymac.dictate

# Prefer the self-signed "TalkToMyMac Dev" identity created by scripts/setup-signing.sh.
# Ad-hoc signing (`--sign -`) makes the designated requirement the binary's cdhash, so
# every rebuild invalidates the app's Microphone and Accessibility grants in TCC. A real
# signing identity keys the requirement to the certificate instead, which is stable.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/TalkToMyMac Dev/ {print $$2; exit}')

all: build

# Deliberately phony rather than a rule on $(APP_BUNDLE): the bundle is a directory, so a
# file target would be considered up to date the moment it exists and would never pick up
# source changes. `swift build` already does its own incremental checking.
build:
	swift build -c release
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp $(SWIFT_BINARY) $(APP_BUNDLE)/Contents/MacOS/TalkToMyMac
ifeq ($(strip $(SIGN_ID)),)
	@echo "⚠️  No \"TalkToMyMac Dev\" signing identity found — falling back to ad-hoc signing."
	@echo "   Permissions (Microphone, Accessibility) will be revoked on every rebuild."
	@echo "   Run 'make setup-signing' once to fix this permanently."
	@codesign --force --sign - --identifier $(CODESIGN_IDENTIFIER) $(APP_BUNDLE)
else
	@echo "Signing $(APP_BUNDLE) with identity $(SIGN_ID)…"
	@codesign --force --sign $(SIGN_ID) --identifier $(CODESIGN_IDENTIFIER) $(APP_BUNDLE)
endif
	@echo "Built $(APP_BUNDLE)"

# One-time setup: creates a self-signed code-signing certificate so TCC permissions
# survive rebuilds. Prompts for your login password.
setup-signing:
	@bash scripts/setup-signing.sh

run: build
	open $(APP_BUNDLE)

test:
	swift test

clean:
	rm -rf build/
	rm -rf .build/
