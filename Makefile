# This Makefile also tricks Travis into not running 'go get' for our
# build. See http://docs.travis-ci.com/user/languages/go/

OBJDIR ?= $(shell pwd)/bin
DESTDIR ?= /usr/local/bin
ARCHIVEDIR ?= /tmp

VERSION ?= 1.0.0
EPOCH ?= 1
MAINTAINER ?= "Community"

CMDS = $(shell find ./cmd -maxdepth 1 -mindepth 1 -type d | grep -v testdata)
CMD_BASENAMES = $(shell echo $(CMDS) | xargs -n1 basename)
CMD_BINS = $(addprefix bin/, $(CMD_BASENAMES) )
OBJECTS = $(CMD_BINS)

# Build environment variables (referencing core/util.go)
COMMIT_ID = $(shell git rev-parse --short=8 HEAD)

BUILD_ID = $(shell git symbolic-ref --short=8 HEAD 2>/dev/null) +$(COMMIT_ID)
BUILD_ID_VAR = github.com/letsencrypt/boulder/core.BuildID

BUILD_HOST = $(shell whoami)@$(shell hostname)
BUILD_HOST_VAR = github.com/letsencrypt/boulder/core.BuildHost

BUILD_TIME = $(shell date -u)
BUILD_TIME_VAR = github.com/letsencrypt/boulder/core.BuildTime

GO_BUILD_FLAGS = -ldflags "-X \"$(BUILD_ID_VAR)=$(BUILD_ID)\" -X \"$(BUILD_TIME_VAR)=$(BUILD_TIME)\" -X \"$(BUILD_HOST_VAR)=$(BUILD_HOST)\""

JENKINS_URL := "https://jenkins.prod.internal.great-it.com"
JENKINS_CRUMB := $(shell curl -u $(JENKINS_USERNAME):$(JENKINS_PASSWORD) --connect-timeout 5 -s "$(JENKINS_URL)/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

.PHONY: all build
all: build

build: $(OBJECTS)

$(OBJDIR):
	@mkdir -p $(OBJDIR)

$(CMD_BINS): build_cmds

build_cmds: | $(OBJDIR)
	GOBIN=$(OBJDIR) GO111MODULE=on go install -mod=vendor $(GO_BUILD_FLAGS) ./...
	cp $(OBJDIR)/boulder-va $(OBJDIR)/boulder-remoteva

# Building an RPM requires `fpm` from https://github.com/jordansissel/fpm
# which you can install with `gem install fpm`.
# It is recommended that maintainers use environment overrides to specify
# Version and Epoch, such as:
#
# VERSION=0.1.9 EPOCH=52 MAINTAINER="$(whoami)" ARCHIVEDIR=/tmp make build rpm
rpm: build
	fpm -f -s dir -t rpm --rpm-digest sha256 --name "boulder" \
		--license "Mozilla Public License v2.0" --vendor "ISRG" \
		--url "https://github.com/letsencrypt/boulder" --prefix=/opt/boulder \
		--version "$(VERSION)" --iteration "$(COMMIT_ID)" --epoch "$(EPOCH)" \
		--package "$(ARCHIVEDIR)/boulder-$(VERSION)-$(COMMIT_ID).x86_64.rpm" \
		--description "Boulder is an ACME-compatible X.509 Certificate Authority" \
		--depends "libtool-ltdl" --maintainer "$(MAINTAINER)" \
		test/config/ sa/_db data/ $(OBJECTS)

.PHONY: lint
lint: Jenkinsfile
ifdef JENKINS_CRUMB
	@curl -X POST -H $(JENKINS_CRUMB) -u $(JENKINS_USERNAME):$(JENKINS_PASSWORD) -F "jenkinsfile=<Jenkinsfile" $(JENKINS_URL)/pipeline-model-converter/validate
else
	@echo "Cannot contact Jenkins at $(JENKINS_URL) to lint Jenkinsfile"
endif
