APP_NAME = Galt
DIST = dist/$(APP_NAME).app

.PHONY: build vendor app run dmg clean

build:
	swift build -c release

vendor:
	bash scripts/fetch-vendor.sh

app:
	bash scripts/package-app.sh

run: app
	open $(DIST)

dmg:
	bash scripts/make-dmg.sh

clean:
	rm -rf .build dist
