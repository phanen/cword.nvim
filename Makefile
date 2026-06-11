export XDG_DATA_HOME ?= $(HOME)/.data
export PJ_ROOT := $(shell pwd)
export NVIM_LOG_FILE ?= $(PJ_ROOT)/.nvimlog

ifeq ($(shell uname -s),Darwin)
    UNAME ?= MACOS
else
    UNAME ?= LINUX
endif

MAKEFLAGS += --no-builtin-rules
MAKEARGS += --warn-undefined-variables

.DEFAULT_GOAL := build

################################################################################
# nvim-test (used by CI; also the runner for Phase 2 specs that need Neovim)
################################################################################

export NVIM_RUNNER_VERSION := v0.12.0
export NVIM_TEST_VERSION ?= v0.12.0

NVIM_TEST := deps/nvim-test

.PHONY: nvim-test
nvim-test: $(NVIM_TEST)
	$(NVIM_TEST)/bin/nvim-test --init

$(NVIM_TEST):
	git clone --depth 1 --branch v1.4.0 https://github.com/lewis6991/nvim-test $@

################################################################################
# Testsuite
################################################################################

# Phase 1 specs are pure Lua (segmentation layer does not touch Neovim),
# so the fast path is plain busted against the system Lua interpreter.
# nvim-test is also wired up so Phase 2 motion specs can run without
# changes to the Makefile.

FILTER ?= .*

.PHONY: test
test:
	@if [ -x "$(NVIM_TEST)/bin/nvim-test" ]; then \
		echo "Running with nvim-test..."; \
		$(NVIM_TEST)/bin/nvim-test test \
			--lpath='$(PWD)/lua/?.lua;$(PWD)/lua/?/init.lua' \
			--filter='$(FILTER)'; \
	else \
		echo "nvim-test not found, falling back to busted (Phase 1 only)..."; \
		if ! command -v busted >/dev/null 2>&1; then \
			echo "busted not found. Install with: luarocks install busted"; \
			exit 1; \
		fi; \
		busted --lpath='lua/?.lua;lua/?/init.lua' --filter='$(FILTER)' test/; \
	fi

.PHONY: test-busted
test-busted:
	@command -v busted >/dev/null 2>&1 || { \
		echo "busted not found. Install with: luarocks install busted"; \
		exit 1; \
	}
	busted --lpath='lua/?.lua;lua/?/init.lua' --filter='$(FILTER)' test/

################################################################################
# Stylua
################################################################################

STYLUA_PLATFORM_MACOS := macos-aarch64
STYLUA_PLATFORM_LINUX := linux-x86_64
STYLUA_PLATFORM := $(STYLUA_PLATFORM_$(UNAME))

STYLUA_VERSION := v2.3.1
STYLUA_ZIP := stylua-$(STYLUA_PLATFORM).zip
STYLUA_URL_BASE := https://github.com/JohnnyMorganz/StyLua/releases/download
STYLUA_URL := $(STYLUA_URL_BASE)/$(STYLUA_VERSION)/$(STYLUA_ZIP)
STYLUA := deps/stylua

# Allow an externally-installed stylua to satisfy the lint target.
STYLUA_BIN := $(or $(shell command -v stylua 2>/dev/null),$(STYLUA))

.INTERMEDIATE: $(STYLUA_ZIP)
$(STYLUA_ZIP):
	wget $(STYLUA_URL)

.PHONY: stylua
stylua: $(STYLUA)

$(STYLUA): $(STYLUA_ZIP)
	unzip $< -d $(dir $@)

LUA_FILES := $(shell find lua test examples -name '*.lua' -type f 2>/dev/null)

.PHONY: format-check
format-check:
	@test -x "$(STYLUA_BIN)" || { \
		echo "stylua not found. Run 'make stylua' to download, or install via 'cargo install stylua'."; \
		exit 1; \
	}
	$(STYLUA_BIN) --check $(LUA_FILES)

.PHONY: format
format:
	@test -x "$(STYLUA_BIN)" || { \
		echo "stylua not found. Run 'make stylua' to download, or install via 'cargo install stylua'."; \
		exit 1; \
	}
	$(STYLUA_BIN) $(LUA_FILES)

################################################################################
# Build
################################################################################

.PHONY: build
build: format-check test

################################################################################
# EmmyLua (optional static analysis)
################################################################################

ifeq ($(shell uname -m),arm64)
    EMMYLUA_ARCH ?= arm64
else
    EMMYLUA_ARCH ?= x64
endif

EMMYLUA_REF := 0.22.0
EMMYLUA_OS ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')

EMMYLUA_DIR := deps/emmylua-$(EMMYLUA_REF)
EMMYLUA_BIN := $(EMMYLUA_DIR)/emmylua_check
EMMYLUA_RELEASE_URL := https://github.com/EmmyLuaLs/emmylua-analyzer-rust/releases/download/$(EMMYLUA_REF)/emmylua_check-$(EMMYLUA_OS)-$(EMMYLUA_ARCH).tar.gz
EMMYLUA_TAR := deps/emmylua_check-$(EMMYLUA_REF)-$(EMMYLUA_OS)-$(EMMYLUA_ARCH).tar.gz

.PHONY: emmylua
emmylua: $(EMMYLUA_BIN)

$(EMMYLUA_BIN):
	mkdir -p $(EMMYLUA_DIR)
	curl -L $(EMMYLUA_RELEASE_URL) -o $(EMMYLUA_TAR)
	tar -xzf $(EMMYLUA_TAR) -C $(EMMYLUA_DIR)

NVIM_TEST_RUNTIME := $(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime

$(NVIM_TEST_RUNTIME): $(NVIM_TEST)
	$^/bin/nvim-test --init

.PHONY: emmylua-check
emmylua-check: $(EMMYLUA_BIN) $(NVIM_TEST_RUNTIME)
	VIMRUNTIME=$(NVIM_TEST_RUNTIME) \
		$(EMMYLUA_BIN) . \
		--ignore 'scratch/**/*' \
		--ignore 'test/**/*'