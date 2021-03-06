# Licensed to Crate (https://crate.io) under one or more contributor license
# agreements.  See the NOTICE file distributed with this work for additional
# information regarding copyright ownership.  Crate licenses this file to you
# under the Apache License, Version 2.0 (the "License"); you may not use this
# file except in compliance with the License.  You may obtain a copy of the
# License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.
#
# However, if you have executed another commercial license agreement with Crate
# these terms will supersede the license and you may use the software solely
# pursuant to the terms of the relevant commercial agreement.


.EXPORT_ALL_VARIABLES:

LOCAL_DIR       := $(patsubst %/src/,%,$(dir $(lastword $(MAKEFILE_LIST))))
SRC_DIR         := $(LOCAL_DIR)/src
ENV_DIR         := $(LOCAL_DIR)/env
ACTIVATE        := $(ENV_DIR)/bin/activate
PYTHON          := python3.7
PIP             := $(PYTHON) -m pip
SPHINXBUILD     := $(ENV_DIR)/bin/sphinx-build
SPHINXAUTOBUILD := $(ENV_DIR)/bin/sphinx-autobuild
AUTOBUILD_OPTS  := --re-ignore '^(?!.+\.rst$$)'
BUILD_DIR       := $(LOCAL_DIR)/.build
SPHINX_ARGS     := . $(BUILD_DIR)
SPHINX_OPTS     := -W -n
RST2HTML        := $(ENV_DIR)/bin/rst2html.py
VALE_VERSION    := 1.4.2
VALE_URL        := https://github.com/errata-ai/vale/releases/download
VALE_URL        := $(VALE_URL)/v$(VALE_VERSION)
VALE_LINUX      := vale_$(VALE_VERSION)_Linux_64-bit.tar.gz
VALE_MACOS      := vale_$(VALE_VERSION)_macOS_64-bit.tar.gz
VALE_WIN        := vale_$(VALE_VERSION)_Windows_64-bit.tar.gz
NO_VALE_FILE    := $(TOP_DIR)/$(DOCS_DIR)/_no_vale # Vale disabled if exists
TOOLS_DIR       := $(LOCAL_DIR)/tools
VALE            := $(TOOLS_DIR)/vale
VALE_OPTS       := --config=$(SRC_DIR)/_vale.ini
LINT            := $(SRC_DIR)/bin/lint
LINT_DIR        := $(LOCAL_DIR)/lint/$(DOCS_DIR)
FSWATCH         := fswatch

# Figure out the OS
ifeq ($(findstring ;,$(PATH)),;)
    # Windows, but not POSIX environment
else
    UNAME := $(shell uname 2>/dev/null || echo Unknown)
    UNAME := $(patsubst CYGWIN%,Windows,$(UNAME))
    UNAME := $(patsubst MSYS%,Windows,$(UNAME))
    UNAME := $(patsubst MINGW%,Windows,$(UNAME))
endif

# Disable Vale
ifneq ($(wildcard $(NO_VALE_FILE)),)
   UNAME := none
endif

# Find all RST source files in `TOP_DIR` (but skip possible locations of
# third-party dependencies)
source_files := $(sort $(shell \
    find '$(TOP_DIR)' \
        -not -path '*/\.*' \
        -not -path '*/site-packages/*' \
        -name '*\.rst' \
        -type f))

# Generate targets
lint_targets := $(patsubst %.rst,%,$(patsubst %,$(LINT_DIR)/%,$(source_files)))

.PHONY: help
help:
	@ printf '\033[33mCrate Docs Build\033[00m\n'
	@ echo
	@ printf 'Run `make <TARGET>`, where <TARGET> is one of:\n'
	@ echo
	@ printf '\033[37m  dev    \033[00m Run a Sphinx development server that'
	@ printf                          ' builds and lints the \n'
	@ printf '\033[37m         \033[00m documentation as you edit the source'
	@ printf                          ' files\n'
	@ echo
	@ printf '\033[37m  html   \033[00m Build the static HTML output\n'
	@ echo
	@ printf '\033[37m  check  \033[00m Build, test, and lint the'
	@ printf                          ' documentation\n'
	@ echo
	@ printf '\033[37m  reset  \033[00m Reset the build cache\n'

$(ACTIVATE):
	$(PYTHON) -m venv $(ENV_DIR)
	. $(ACTIVATE) && \
	    $(PIP) install --upgrade pip

$(RST2HTML) $(SPHINXBUILD) $(SPHINXAUTOBUILD): $(ACTIVATE)
	. $(ACTIVATE) && \
	    $(PIP) install -r $(SRC_DIR)/requirements.txt
	@ # We change to `TOP_DIR` to mimic how Read the Docs does it
	. $(ACTIVATE) && cd $(TOP_DIR) && \
	    $(PIP) install -r $(DOCS_DIR)/requirements.txt

ifeq ($(UNAME),Linux)
$(VALE):
	mkdir -p $(TOOLS_DIR)
	curl -L $(VALE_URL)/$(VALE_LINUX) -o $(TOOLS_DIR)/$(VALE_LINUX)
	cd $(TOOLS_DIR) && tar -xzf $(VALE_LINUX)
endif

ifeq ($(UNAME),Darwin)
$(VALE):
	mkdir -p $(TOOLS_DIR)
	curl -L $(VALE_URL)/$(VALE_MACOS) -o $(TOOLS_DIR)/$(VALE_MACOS)
	cd $(TOOLS_DIR) && tar -xzf $(VALE_MACOS)
endif

# Disable Vale by mocking the executable
ifeq ($(UNAME),none)
$(VALE):
	mkdir -p $(TOOLS_DIR)
	ln -s `which true` $(VALE)
endif

.PHONY: vale
vale: $(ACTIVATE) $(VALE)
	@ if test ! -x $(VALE); then \
	    printf 'No rules to install Vale on your operating system.\n'; \
	    exit 1; \
	fi
	@ # Force an empty line after environment setup and before linting happens
	@ # when running `make dev` for the first time
	@ echo

$(LINT_DIR):
	@ mkdir -p $(LINT_DIR)

.PHONY: lint-deps
lint-deps: $(LINT_DIR) vale

# Lint an RST file and dump the output
$(LINT_DIR)/%: %.rst
	@ if test -n '$(dir $@)'; then \
	    mkdir -p '$(dir $@)'; \
	fi
	@ . $(ACTIVATE) && \
	    $(LINT) '$<' '$@'

.PHONY: lint
lint: lint-deps $(lint_targets)

# If you are having problems with the `linkcheck` target, you might
# want to configure `linkcheck_ignore` in your `conf.py` file.
.PHONY: html linkcheck
html linkcheck: $(ACTIVATE) $(SPHINXBUILD)
	@ . $(ACTIVATE) && \
	    $(SPHINXBUILD) $(SPHINX_ARGS) $(SPHINX_OPTS) $(O)

.PHONY: autobuild-deps
autobuild-deps: $(SPHINXAUTOBUILD)

.PHONY: autobuild
autobuild: autobuild-deps
	@ . $(ACTIVATE) && \
	    $(SPHINXAUTOBUILD) $(SPHINX_ARGS) $(SPHINX_OPTS) $(AUTOBUILD_OPTS) $(O)

.PHONY: lint-watch
lint-watch: lint-deps
	@ if test ! -x "`which $(FSWATCH)`"; then \
	    printf '\033[31mYou must have fswatch installed.\033[00m\n'; \
	    exit 1; \
	fi
	@ $(FSWATCH) $(BUILD_DIR)/sitemap.xml | while read num; do \
	    cd $(TOP_DIR)/$(DOCS_DIR) && $(MAKE) lint; \
	done || true

.PHONY: dev
dev:
	@ # Build dependencies first
	@ $(MAKE) autobuild-deps
	@ $(MAKE) lint-deps
	@ # Force existence of sitemap.xml prior to running lint-watch
	@ mkdir -p $(BUILD_DIR)
	@ touch $(BUILD_DIR)/sitemap.xml
	@ # Force linting for all files
	@ $(MAKE) delint > /dev/null
	@ $(MAKE) lint
	@ # Run `autobuild` and `lint-watch` simultaneously with the `-j` flag.
	@ # Both output to STDOUT and STDERR. To make this less confusing,
	@ # `lint-watch` watches the sitemap file that Sphinx builds at the end of
	@ # each build iteration. So Sphinx should wake up first, and then the
	@ # linter. The resulting output flows quite nicely.
	@ $(MAKE) -j autobuild lint-watch

.PHONY: check
check: html linkcheck
	@ # Force linting for all files
	@ $(MAKE) delint > /dev/null
	@ $(MAKE) lint

# Alias for commonly used Make target
.PHONY: test
test: check

.PHONY: delint
delint: $(LINT_DIR)
	@ rm -rf $(LINT_DIR)
	@ # Remove files left behind by older version of the build system
	@ find $(TOP_DIR) -type f -name '*\.lint' -delete
