# Onyx — a chromeless, typeset notes app for Markdown vaults.
# Empty: open your remembered vault (or ~/Notes). Tests pass VAULT=/tmp/onyx-vault explicitly.
VAULT ?=
TEST_VAULT ?= /tmp/onyx-vault
ARGS ?=
# UNIVERSAL=1 (or `make release`) builds an arm64 + x86_64 binary.
# `make app` stays native so everyday rebuilds stay fast.
UNIVERSAL ?= 0
# make install: where the universal app goes. DESTDIR stages under a prefix.
INSTALL_DIR ?= /Applications
DESTDIR ?=
NO_QUIT ?=
RELAUNCH ?=

.PHONY: build app run dev test icon demo-vault clean install uninstall release

build:
	UNIVERSAL=$(UNIVERSAL) ./scripts/build-binary.sh release

app: build icon
	UNIVERSAL=$(UNIVERSAL) ./scripts/bundle.sh release

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
	node --test Tests/reader

icon:
	@test -f Resources/AppIcon.icns || { echo "missing Resources/AppIcon.icns"; exit 1; }

# A disposable copy of the neutral parts of ~/Notes for testing (read-only on the source).
demo-vault:
	rm -rf /tmp/onyx-vault && mkdir -p /tmp/onyx-vault/Daily /tmp/onyx-vault/Writing /tmp/onyx-vault/.obsidian
	cd ~/Notes && rsync -a Knowledge Projects Library Home.md /tmp/onyx-vault/
	cd ~/Notes && rsync -a Writing/Essays Writing/Poetry Writing/Music "Writing/Artificial Intelligence" Writing/Writing.md /tmp/onyx-vault/Writing/
	cd ~/Notes/.obsidian && cp app.json appearance.json bookmarks.json daily-notes.json /tmp/onyx-vault/.obsidian/

# Universal app (same build as `make release`, no zip) into $(INSTALL_DIR)/Onyx.app.
# Quits a running Onyx gracefully only for the real /Applications (NO_QUIT=1 skips);
# RELAUNCH=1 reopens it afterwards if it was running.
install:
	$(MAKE) app UNIVERSAL=1
	INSTALL_DIR="$(INSTALL_DIR)" DESTDIR="$(DESTDIR)" NO_QUIT="$(NO_QUIT)" RELAUNCH="$(RELAUNCH)" ./scripts/install.sh install

uninstall:
	INSTALL_DIR="$(INSTALL_DIR)" DESTDIR="$(DESTDIR)" NO_QUIT="$(NO_QUIT)" ./scripts/install.sh uninstall

clean:
	rm -rf .build build
