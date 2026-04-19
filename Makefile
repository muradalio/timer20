.PHONY: build app install run run-installed clean

build:
	swift build

app:
	./Scripts/build-app.sh release

install:
	./Scripts/install-app.sh

run: app
	open build/Timer20.app

run-installed:
	open /Applications/Timer20.app

clean:
	rm -rf .build build
