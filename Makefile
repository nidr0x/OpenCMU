SHELL := /bin/sh

.PHONY: all test dist collect clean

all: test

test:
	sh tests/smoke.sh

dist:
	sh builder/build-usb.sh
	sh builder/verify-usb.sh dist/opencmu-usb
	@command -v python3 >/dev/null 2>&1 || { echo "python3 is required for the .up builder" >&2; exit 1; }
	python3 builder/make-up.py --out dist/opencmu.up --force

# Separate, opt-in payload that only collects stock files for analysis.
collect:
	sh builder/build-collect.sh

clean:
	rm -rf dist
