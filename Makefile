# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024 Matteo Cavestri
#
# Makefile for Userland Utilities

# Configuration
PREFIX      ?= /usr/local
BINDIR      ?= $(PREFIX)/bin
MANDIR      ?= $(PREFIX)/share/man
DESTDIR     ?=

# Build configuration
ZIG         ?= zig
ZIG_FLAGS   ?= -Doptimize=ReleaseSafe
BUILD_DIR   = zig-out/bin
MAN_SRC     = man/coreutils

# Utilities to build
UTILITIES   = true false pwd echo cat ls mkdir touch

# Man pages
MAN_PAGES   = $(wildcard $(MAN_SRC)/*.1)

# Colors for output
COLOR_RESET = \033[0m
COLOR_BOLD  = \033[1m
COLOR_GREEN = \033[32m
COLOR_BLUE  = \033[34m

# Phony targets
.PHONY: all build test test-posix man install uninstall clean help

# Default target
all: build

# Build all utilities
build:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Building utilities...$(COLOR_RESET)"
	@$(ZIG) build $(ZIG_FLAGS)
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Build complete$(COLOR_RESET)"

# Run Zig integration tests
test: build
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Running integration tests...$(COLOR_RESET)"
	@$(ZIG) build test
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Tests passed$(COLOR_RESET)"

# Run POSIX compliance tests
test-posix: build
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Running POSIX compliance tests...$(COLOR_RESET)"
	@./utils/check-posix
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ POSIX compliance verified$(COLOR_RESET)"

# Run all tests
test-all: test test-posix
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ All tests passed$(COLOR_RESET)"

# Generate/verify man pages
man:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Verifying man pages...$(COLOR_RESET)"
	@for page in $(MAN_PAGES); do \
		echo "  Checking $$page"; \
		if ! man -l $$page >/dev/null 2>&1; then \
			echo "✗ Invalid man page: $$page"; \
			exit 1; \
		fi; \
	done
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ All man pages valid$(COLOR_RESET)"

# Install utilities and man pages
install: build man
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Installing to $(DESTDIR)$(PREFIX)...$(COLOR_RESET)"
	@echo "  BINDIR: $(DESTDIR)$(BINDIR)"
	@echo "  MANDIR: $(DESTDIR)$(MANDIR)"
	@install -d "$(DESTDIR)$(BINDIR)"
	@for util in $(UTILITIES); do \
		echo "  Installing $(DESTDIR)$(BINDIR)/$$util"; \
		install -m 755 "$(BUILD_DIR)/$$util" "$(DESTDIR)$(BINDIR)/$$util"; \
	done
	@install -d "$(DESTDIR)$(MANDIR)/man1"
	@for page in $(MAN_PAGES); do \
		filename=$$(basename "$$page"); \
		echo "  Installing $(DESTDIR)$(MANDIR)/man1/$$filename"; \
		install -m 644 "$$page" "$(DESTDIR)$(MANDIR)/man1/$$filename"; \
	done
	@if [ -z "$(DESTDIR)" ] && command -v mandb >/dev/null 2>&1; then \
		echo "  Updating man database..."; \
		mandb -q 2>/dev/null || true; \
	fi
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Installation complete$(COLOR_RESET)"

# Uninstall utilities and man pages
uninstall:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Uninstalling from $(DESTDIR)$(PREFIX)...$(COLOR_RESET)"
	@for util in $(UTILITIES); do \
		if [ -f "$(DESTDIR)$(BINDIR)/$$util" ]; then \
			echo "  Removing $(DESTDIR)$(BINDIR)/$$util"; \
			rm -f "$(DESTDIR)$(BINDIR)/$$util"; \
		fi; \
	done
	@for page in $(MAN_PAGES); do \
		filename=$$(basename "$$page"); \
		if [ -f "$(DESTDIR)$(MANDIR)/man1/$$filename" ]; then \
			echo "  Removing $(DESTDIR)$(MANDIR)/man1/$$filename"; \
			rm -f "$(DESTDIR)$(MANDIR)/man1/$$filename"; \
		fi; \
	done
	@if [ -z "$(DESTDIR)" ] && command -v mandb >/dev/null 2>&1; then \
		echo "  Updating man database..."; \
		mandb -q 2>/dev/null || true; \
	fi
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Uninstallation complete$(COLOR_RESET)"

# Clean build artifacts
clean:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Cleaning build artifacts...$(COLOR_RESET)"
	@rm -rf zig-out .zig-cache
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Clean complete$(COLOR_RESET)"

# Display help
help:
	@echo "$(COLOR_BOLD)Userland Utilities - Makefile$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Usage:$(COLOR_RESET)"
	@echo "  make [target] [VAR=value]"
	@echo ""
	@echo "$(COLOR_BOLD)Targets:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)build$(COLOR_RESET)        Build all utilities (default)"
	@echo "  $(COLOR_GREEN)test$(COLOR_RESET)         Run Zig integration tests"
	@echo "  $(COLOR_GREEN)test-posix$(COLOR_RESET)   Run POSIX compliance tests"
	@echo "  $(COLOR_GREEN)test-all$(COLOR_RESET)     Run all tests"
	@echo "  $(COLOR_GREEN)man$(COLOR_RESET)          Verify man pages"
	@echo "  $(COLOR_GREEN)install$(COLOR_RESET)      Install utilities and man pages"
	@echo "  $(COLOR_GREEN)uninstall$(COLOR_RESET)    Remove installed files"
	@echo "  $(COLOR_GREEN)clean$(COLOR_RESET)        Remove build artifacts"
	@echo "  $(COLOR_GREEN)help$(COLOR_RESET)         Display this help message"
	@echo ""
	@echo "$(COLOR_BOLD)Variables:$(COLOR_RESET)"
	@echo "  $(COLOR_BLUE)PREFIX$(COLOR_RESET)       Installation prefix (default: /usr/local)"
	@echo "  $(COLOR_BLUE)BINDIR$(COLOR_RESET)       Binary installation directory (default: PREFIX/bin)"
	@echo "  $(COLOR_BLUE)MANDIR$(COLOR_RESET)       Man page directory (default: PREFIX/share/man)"
	@echo "  $(COLOR_BLUE)DESTDIR$(COLOR_RESET)      Staging directory for package builds"
	@echo "  $(COLOR_BLUE)ZIG$(COLOR_RESET)          Zig compiler command (default: zig)"
	@echo "  $(COLOR_BLUE)ZIG_FLAGS$(COLOR_RESET)    Additional Zig build flags"
	@echo ""
	@echo "$(COLOR_BOLD)Examples:$(COLOR_RESET)"
	@echo "  make build"
	@echo "  make test-all"
	@echo "  make install PREFIX=/usr"
	@echo "  sudo make install"
	@echo "  make install DESTDIR=/tmp/staging PREFIX=/usr"
	@echo ""
	@echo "$(COLOR_BOLD)License:$(COLOR_RESET) GPL-3.0-or-later"
	@echo "$(COLOR_BOLD)Author:$(COLOR_RESET)  Matteo Cavestri"
