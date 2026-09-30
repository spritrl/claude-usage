APP := build/ClaudeUsage.app

.PHONY: build bundle run install clean

build:
	swift build -c release

bundle:
	./scripts/bundle.sh

run: bundle
	-pkill -x ClaudeUsage
	open $(APP)

install: bundle
	-pkill -x ClaudeUsage
	rm -rf /Applications/ClaudeUsage.app
	cp -R $(APP) /Applications/
	open /Applications/ClaudeUsage.app

clean:
	rm -rf .build build
