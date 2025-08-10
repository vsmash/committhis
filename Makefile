# Makefile for bashmaiass

ENTRY ?= maiass.sh
OUT ?= maiass.bundle.sh

.PHONY: bundle clean

bundle:
	@./scripts/bundle-bash.sh $(ENTRY) $(OUT)
	@echo "Created $(OUT)"

clean:
	rm -f $(OUT)
