STORE_ID := hastrekha

.PHONY: run build test analyze clean

run:
	flutter pub get && flutter run

build:
	flutter pub get && flutter build apk --release

test:
	flutter test

analyze:
	flutter analyze

clean:
	flutter clean
	rm -rf dist

# deploy, release, bump, store-check, store-meta, version
include store.mk
