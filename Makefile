# Onyx — a chromeless, typeset notes app for Markdown vaults.
# Empty: open your remembered vault (or ~/Notes). Tests pass VAULT=/tmp/onyx-vault explicitly.
VAULT ?=
TEST_VAULT ?= /tmp/onyx-vault
ARGS ?=
# UNIVERSAL=1 (or `make release`) builds an arm64 + x86_64 binary.
# `make app` stays native so everyday rebuilds stay fast.
UNIVERSAL ?= 0
# make install is universal unless ONE_ARCH=1 or ARCH=arm64|x86_64.
# `make install-native` is an alias for ONE_ARCH=1 (this machine's arch).
ONE_ARCH ?= 0
ARCH ?=
HOST_ARCH := $(shell uname -m)
# make install: where the app goes. DESTDIR stages under a prefix.
INSTALL_DIR ?= /Applications
DESTDIR ?=
NO_QUIT ?=
RELAUNCH ?=

# `make install` stays universal unless a one-arch flag is set.
INSTALL_UNIVERSAL = 1
ifeq ($(ONE_ARCH),1)
INSTALL_UNIVERSAL = 0
endif
ifneq ($(strip $(ARCH)),)
INSTALL_UNIVERSAL = 0
endif
INSTALL_ARCH = $(strip $(ARCH))
ifeq ($(INSTALL_UNIVERSAL),0)
ifeq ($(INSTALL_ARCH),)
INSTALL_ARCH = $(HOST_ARCH)
endif
endif

.PHONY: build app run dev test icon demo-vault clean install install-native uninstall release ios

build:
	UNIVERSAL=$(UNIVERSAL) ARCH="$(ARCH)" ./scripts/build-binary.sh release

app: build icon
	UNIVERSAL=$(UNIVERSAL) ARCH="$(ARCH)" ./scripts/bundle.sh release

# Universal (Apple silicon + Intel) app, plus the GitHub Releases zip.
# Asset name must stay Onyx-<version>-macOS.zip; the auto-updater looks for it.
release:
	$(MAKE) app UNIVERSAL=1
	ditto -c -k --keepParent build/Onyx.app "build/Onyx-$$(cat VERSION)-macOS.zip"
	@echo "Universal app: build/Onyx.app"
	@lipo -info build/Onyx.app/Contents/MacOS/Onyx
	@echo "Release zip: build/Onyx-$$(cat VERSION)-macOS.zip"

# Open the built app on your vault (remembered, else ~/Notes). With VAULT set, it opens that
# folder without changing the vault Onyx remembers (handy for test copies).
run: app
	open -n build/Onyx.app --args $(if $(VAULT),--vault "$(VAULT)") $(ARGS)

# The disposable demo/test copy, never ~/Notes. ONYX_ALLOW_MULTIPLE so a
# test launch cannot quit a running Onyx someone is using.
run-test: app
	open -n --env ONYX_NO_DEFAULT_VAULT=1 --env ONYX_ALLOW_MULTIPLE=1 build/Onyx.app --args --vault "$(TEST_VAULT)" $(ARGS)

# Your real vault: whatever Onyx last opened (or the welcome screen).
open: app
	open build/Onyx.app

dev:
	swift build && ONYX_NO_DEFAULT_VAULT=1 ONYX_ALLOW_MULTIPLE=1 ./.build/debug/Onyx --vault "$(or $(VAULT),$(TEST_VAULT))" $(ARGS)

test:
	swift test
	node --test Tests/reader Tests/extension

icon:
	@test -f Resources/AppIcon.icns || { echo "missing Resources/AppIcon.icns"; exit 1; }

# A disposable copy of the neutral parts of ~/Notes for testing (read-only on the source).
demo-vault:
	rm -rf /tmp/onyx-vault && mkdir -p /tmp/onyx-vault/Daily /tmp/onyx-vault/Writing /tmp/onyx-vault/.obsidian
	cd ~/Notes && rsync -a Knowledge Projects Library Home.md /tmp/onyx-vault/
	cd ~/Notes && rsync -a Writing/Essays Writing/Poetry Writing/Music "Writing/Artificial Intelligence" Writing/Writing.md /tmp/onyx-vault/Writing/
	cd ~/Notes/.obsidian && cp app.json appearance.json bookmarks.json daily-notes.json /tmp/onyx-vault/.obsidian/

# App (universal by default; same build as `make release`, no zip) into $(INSTALL_DIR)/Onyx.app.
# ONE_ARCH=1 or `make install-native` builds only this machine's architecture (`uname -m`);
# ARCH=arm64 or ARCH=x86_64 selects the slice. Quits a running Onyx gracefully only for
# the real /Applications (NO_QUIT=1 skips); RELAUNCH=1 reopens it afterwards if it was running.
install:
	$(MAKE) app UNIVERSAL=$(INSTALL_UNIVERSAL) ARCH="$(INSTALL_ARCH)"
	INSTALL_DIR="$(INSTALL_DIR)" DESTDIR="$(DESTDIR)" NO_QUIT="$(NO_QUIT)" RELAUNCH="$(RELAUNCH)" UNIVERSAL="$(INSTALL_UNIVERSAL)" ONE_ARCH="$(ONE_ARCH)" ARCH="$(INSTALL_ARCH)" ./scripts/install.sh install

install-native:
	$(MAKE) install ONE_ARCH=1

uninstall:
	INSTALL_DIR="$(INSTALL_DIR)" DESTDIR="$(DESTDIR)" NO_QUIT="$(NO_QUIT)" ./scripts/install.sh uninstall

# iOS simulator app (branch ios). Regenerates Onyx.xcodeproj from project.yml.
# Does not touch /Applications or a running Mac Onyx.
# Ad-hoc signed ("Sign to Run Locally", no team): the simulator then grants the app its application-identifier,
# which the Keychain needs. An unsigned build (CODE_SIGNING_ALLOWED=NO) gets errSecMissingEntitlement (-34018).
ios:
	xcodegen generate
	xcodebuild -project Onyx.xcodeproj -scheme OnyxMobile -destination 'generic/platform=iOS Simulator' -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

clean:
	rm -rf .build build
