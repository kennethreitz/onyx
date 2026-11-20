# Onyx — a chromeless, typeset notes app for Markdown vaults.
VAULT ?= /tmp/onyx-vault
ARGS ?=

.PHONY: build app run dev test icon demo-vault clean install

build:
	swift build -c release

app: build icon
	./scripts/bundle.sh release

# Open the built app. With VAULT set, it opens that folder without changing
# the vault Onyx remembers (handy for test copies).
run: app
	open -n build/Onyx.app --args --vault "$(VAULT)" $(ARGS)

# Your real vault: whatever Onyx last opened (or the welcome screen).
open: app
	open build/Onyx.app

dev:
	swift build && ./.build/debug/Onyx --vault "$(VAULT)" $(ARGS)

test:
	swift test

icon:
	@[ -f build/Onyx.icns ] || swift scripts/make-icon.swift build

# A disposable copy of the neutral parts of ~/Notes for testing (read-only on the source).
demo-vault:
	rm -rf /tmp/onyx-vault && mkdir -p /tmp/onyx-vault/Daily /tmp/onyx-vault/Writing /tmp/onyx-vault/.obsidian
	cd ~/Notes && rsync -a Knowledge Projects Library Home.md /tmp/onyx-vault/
	cd ~/Notes && rsync -a Writing/Essays Writing/Poetry Writing/Music "Writing/Artificial Intelligence" Writing/Writing.md /tmp/onyx-vault/Writing/
	cd ~/Notes/.obsidian && cp app.json appearance.json bookmarks.json daily-notes.json /tmp/onyx-vault/.obsidian/

install: app
	rm -rf /Applications/Onyx.app && cp -R build/Onyx.app /Applications/

clean:
	rm -rf .build build
