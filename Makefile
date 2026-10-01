.PHONY: all build clean run test setup-signing install uninstall

APP_NAME = TalkToMyMac
APP_BUNDLE = build/$(APP_NAME).app
INSTALL_DIR = /Applications
INSTALLED_APP = $(INSTALL_DIR)/$(APP_NAME).app
SWIFT_BUILD_DIR = .build/release
SWIFT_BINARY = $(SWIFT_BUILD_DIR)/$(APP_NAME)
CODESIGN_IDENTIFIER = com.talktomymac.dictate
ICON_SOURCE = Resources/AppIcon.png
ICON_ICNS = build/AppIcon.icns
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Prefer the self-signed "TalkToMyMac Dev" identity created by scripts/setup-signing.sh.
# Ad-hoc signing (`--sign -`) makes the designated requirement the binary's cdhash, so
# every rebuild invalidates the app's Microphone and Accessibility grants in TCC. A real
# signing identity keys the requirement to the certificate instead, which is stable.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/TalkToMyMac Dev/ {print $$2; exit}')

all: build

# Deliberately phony rather than a rule on $(APP_BUNDLE): the bundle is a directory, so a
# file target would be considered up to date the moment it exists and would never pick up
# source changes. `swift build` already does its own incremental checking.
build: $(ICON_ICNS)
	swift build -c release
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp $(ICON_ICNS) $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp $(SWIFT_BINARY) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
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

# A real file target, so the .icns is only rebuilt when the master PNG changes.
# To change the artwork, edit scripts/generate-icon.swift and re-run it, or drop in any
# 1024×1024 PNG at $(ICON_SOURCE).
$(ICON_ICNS): $(ICON_SOURCE)
	@rm -rf build/AppIcon.iconset
	@mkdir -p build/AppIcon.iconset
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size $< --out build/AppIcon.iconset/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) $< --out build/AppIcon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	@iconutil -c icns build/AppIcon.iconset -o $@
	@rm -rf build/AppIcon.iconset

# One-time setup: creates a self-signed code-signing certificate so TCC permissions
# survive rebuilds. Prompts for your login password. Safe to re-run.
setup-signing:
	@bash scripts/setup-signing.sh

# First-time and repeat installs alike: ensure a signing identity exists, build, and copy
# the signed app into /Applications so it shows up with its icon in Finder, Spotlight,
# Launchpad and System Settings (Privacy & Security, Login Items).
#
# `build` runs via a recursive $(MAKE) because SIGN_ID is resolved when the Makefile is
# parsed — a plain prerequisite would still see the pre-setup (empty) identity and fall
# back to ad-hoc signing on the very first install.
install:
	@bash scripts/setup-signing.sh
	@$(MAKE) --no-print-directory build
	-@pkill -x $(APP_NAME) && sleep 0.5 || true
	@echo "Installing to $(INSTALLED_APP)…"
	@rm -rf "$(INSTALLED_APP)"
	@ditto $(APP_BUNDLE) "$(INSTALLED_APP)"
	@$(LSREGISTER) -f "$(INSTALLED_APP)"
	@echo "✅ Installed $(INSTALLED_APP)"
	open "$(INSTALLED_APP)"

uninstall:
	-@pkill -x $(APP_NAME) && sleep 0.5 || true
	@if [ -d "$(INSTALLED_APP)" ]; then \
		$(LSREGISTER) -u "$(INSTALLED_APP)"; \
		rm -rf "$(INSTALLED_APP)"; \
		echo "Removed $(INSTALLED_APP)"; \
	else \
		echo "$(INSTALLED_APP) is not installed."; \
	fi
	@echo "Settings, recordings, and the signing certificate were left in place."

# `open` only re-activates an already-running instance, which would silently keep the old
# binary alive — quit it first so the fresh build is what actually launches.
run: build
	-@pkill -x $(APP_NAME) && sleep 0.5 || true
	open $(APP_BUNDLE)

test:
	swift test

clean:
	rm -rf build/
	rm -rf .build/
