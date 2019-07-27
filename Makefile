.PHONY: morley test haddock haddock-no-deps stylish lint clean all

# Build target from the common utility Makefile
MAKEU = $(MAKE) -C make/

MAKE_PACKAGE = $(MAKEU) PACKAGE=morley

morley:
	$(MAKE_PACKAGE) dev
test:
	$(MAKE_PACKAGE) test
test-dumb-term:
	$(MAKE_PACKAGE) test-dumb-term
test-hide-successes:
	$(MAKE_PACKAGE) test-hide-successes
haddock:
	$(MAKE_PACKAGE) haddock
haddock-no-deps:
	$(MAKE_PACKAGE) haddock-no-deps
stylish:
	$(MAKE_PACKAGE) stylish
lint:
	$(MAKE_PACKAGE) lint
clean:
	$(MAKE_PACKAGE) clean

all:
	$(MAKEU) PACKAGE=""
test-all:
	$(MAKEU) test PACKAGE=""
