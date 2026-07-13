all: build

ifndef GOPATH
$(error Environment variable GOPATH is not set)
endif

SHELL := /bin/bash
.DEFAULT_GOAL := all
S3_PLUGIN=gpbackup_s3_plugin
DIR_PATH=$(shell dirname `pwd`)
BIN_DIR=$(shell echo $${GOPATH:-~/go} | awk -F':' '{ print $$1 "/bin"}')

GIT_VERSION := $(or $(shell git describe --tags 2>/dev/null | perl -pe 's/(.*)-([0-9]*)-(g[0-9a-f]*)/\1+dev.\2.\3/'),$(shell cat VERSION))
ifeq ($(GIT_VERSION),)
$(error GIT_VERSION is empty: run from a git repo with tags or provide a VERSION file)
endif

PLUGIN_VERSION_STR="-X github.com/GreengageDB/gpbackup-s3-plugin/s3plugin.Version=$(GIT_VERSION)"
GOLANG_LINTER=$(GOPATH)/bin/golangci-lint
GINKGO=$(GOPATH)/bin/ginkgo
GOIMPORTS=$(GOPATH)/bin/goimports
GO_ENV=GO111MODULE=on # ensure the project still compiles in $GOPATH/src using golang versions 1.12 and below
DEBUG=-gcflags=all="-N -l"

# Prefer gpsync as the newer utility, fall back to gpscp if not present (older installs)
ifeq (, $(shell which gpsync))
COPYUTIL=gpscp
else
COPYUTIL=gpsync
endif

LINTER_VERSION=1.16.0
$(GOLANG_LINTER) :
		curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOPATH)/bin v${LINTER_VERSION}

depend :
		$(GO_ENV) go mod download

$(GINKGO) :
		$(GO_ENV) go install github.com/onsi/ginkgo/v2/ginkgo@latest

$(GOIMPORTS) :
		$(GO_ENV) go install golang.org/x/tools/cmd/goimports

format : $(GOIMPORTS)
		goimports -w .
		gofmt -w -s .

lint : $(GOLANG_LINTER)
		golangci-lint run --tests=false

unit : depend $(GINKGO)
		$(GO_ENV) ginkgo -r --keep-going --randomize-suites --randomize-all --no-color s3plugin 2>&1

test : unit

debug : depend
		$(GO_ENV) go build $(DEBUG) -o $(BIN_DIR)/$(S3_PLUGIN) -ldflags $(PLUGIN_VERSION_STR)

build : depend
		$(GO_ENV) go build -o $(BIN_DIR)/$(S3_PLUGIN) -ldflags $(PLUGIN_VERSION_STR)

build_linux : depend
		env GOOS=linux GOARCH=amd64 $(GO_ENV) go build -o $(S3_PLUGIN) -ldflags $(PLUGIN_VERSION_STR)

build_mac : depend
		env GOOS=darwin GOARCH=amd64 $(GO_ENV) go build -o $(BIN_DIR)/$(S3_PLUGIN) -ldflags $(PLUGIN_VERSION_STR)

install : build
		@psql -t -d template1 -c 'select distinct hostname from gp_segment_configuration' > /tmp/seg_hosts 2>/dev/null; \
		if [ $$? -eq 0 ]; then \
			$(COPYUTIL) -f /tmp/seg_hosts $(BIN_DIR)/$(S3_PLUGIN) =:$(GPHOME)/bin/$(S3_PLUGIN); \
			if [ $$? -eq 0 ]; then \
				echo 'Successfully copied gpbackup_s3_plugin to $(GPHOME) on all segments'; \
			else \
				echo 'Failed to copy gpbackup_s3_plugin to $(GPHOME)'; \
			fi; \
		else \
			echo 'Database is not running, please start the database and run this make target again'; \
		fi; \
		rm /tmp/seg_hosts

#---------------------------------------------------------------------
# Packaging targets with changelog options
#---------------------------------------------------------------------

# Metadata vars
GPROOT			:= /opt/greengagedb
PACKAGE_NAME	:= $(shell grep '^Package:' debian/control | head -1 | awk '{print $$2}')
MAINTAINER		:= $(shell grep '^Maintainer:' debian/control | sed 's/Maintainer: //')
DATE_RFC		:= $(shell date -R)
DISTRO_CODENAME := $(shell lsb_release -sc)
IS_RELEASE      := $(if $(findstring ~dev,$(GIT_VERSION)),no,yes)
BUILD_TYPE      := $(if $(filter yes,$(IS_RELEASE)),Release build,Development build)
DEB_TOPDIR		?= $(CURDIR)/../deb-packages
RPM_TOPDIR		?= $(CURDIR)/../RPM

# Generate for Dockerfile where .git is absent
VERSION :
	@echo "Update $@"
	@echo "$(GIT_VERSION)" > $@
	@cat $@

debian/changelog:
	@echo "$(PACKAGE_NAME) ($(GIT_VERSION)) $(DISTRO_CODENAME); urgency=low" > $@
	@echo "" >> $@
	@echo "  * $(BUILD_TYPE)" >> $@
	@echo "" >> $@
	@echo " -- $(MAINTAINER)  $(DATE_RFC)" >> $@

debian/install:
	@echo "$(PACKAGE_NAME)/* /" > $@

# Default packaging target
pkg : pkg-info pkg-deb

# Display package info
pkg-info :
	@echo "PACKAGE_NAME: $(PACKAGE_NAME)"
	@echo "MAINTAINER: $(MAINTAINER)"
	@echo "DATE_RFC: $(DATE_RFC)"
	@echo "GIT_VERSION: $(GIT_VERSION)"
	@echo "DISTRO_CODENAME: $(DISTRO_CODENAME)"
	@echo "IS_RELEASE: $(IS_RELEASE)"
	@echo "BUILD_TYPE: $(BUILD_TYPE)"

# Build Debian package
pkg-deb : debian/changelog debian/install
	@GPROOT="$(GPROOT)" PACKAGE_NAME="$(PACKAGE_NAME)" debuild --preserve-env -us -uc -b
	@mkdir -p $(DEB_TOPDIR)
	@find $(CURDIR)/../ -maxdepth 1 -type f \( -name "*.deb" \
											-o -name "*.ddeb" \
											-o -name "*.build" \
											-o -name "*.buildinfo" \
											-o -name "*.changes" \) \
											-exec mv -f {} $(DEB_TOPDIR)/ \;

.PHONY: debian/changelog debian/install pkg pkg-info pkg-deb

clean :
		# Build artifacts
		rm -f $(BIN_DIR)/$(S3_PLUGIN)
		# Test artifacts
		rm -rf /tmp/go-build*
		rm -rf /tmp/gexec_artifacts*
		rm -rf /tmp/ginkgo*
		@if [ -d .git ] ; then rm -f VERSION; fi
