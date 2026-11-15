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

# Opt-in static lint of every patch anchor against a stock rootfs.
# Requires OPENCMU_STOCK_ROOT (exits 2 when unset); never fails CI without it.
check-anchors:
	@if [ -z "$$OPENCMU_STOCK_ROOT" ]; then \
		echo "check-anchors: set OPENCMU_STOCK_ROOT to a stock rootfs" >&2; \
		exit 2; \
	fi
	python3 builder/check-anchors.py

clean:
	rm -rf dist
