# Onyx — a chromeless, typeset notes app for Markdown vaults.
# Empty: open your remembered vault (or ~/Notes). Tests pass VAULT=/tmp/onyx-vault explicitly.
VAULT ?=
TEST_VAULT ?= /tmp/onyx-vault
ARGS ?=

.PHONY: build app run dev test icon demo-vault clean install

build:
	swift build -c release

app: build icon
	./scripts/bundle.sh release

# Open the built app on your vault (remembered, else ~/Notes). With VAULT set, it opens that
# folder without changing the vault Onyx remembers (handy for test copies).
run: app
	open -n build/Onyx.app --args $(if $(VAULT),--vault "$(VAULT)") $(ARGS)

# The disposable demo/test copy, never ~/Notes.
run-test: app
	open -n --env ONYX_NO_DEFAULT_VAULT=1 build/Onyx.app --args --vault "$(TEST_VAULT)" $(ARGS)

# Your real vault: whatever Onyx last opened (or the welcome screen).
open: app
	open build/Onyx.app

dev:
	swift build && ONYX_NO_DEFAULT_VAULT=1 ./.build/debug/Onyx --vault "$(or $(VAULT),$(TEST_VAULT))" $(ARGS)

test:
	swift test
	node --test Tests/reader

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
