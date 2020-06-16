SHELL = bash

GOOS?=$(shell go env GOOS)
GOARCH?=$(shell go env GOARCH)
GOPATH=$(shell go env GOPATH)
GOTAGS ?=
GOTOOLS = \
	github.com/magiconair/vendorfmt/cmd/vendorfmt \
	github.com/mitchellh/gox \
	golang.org/x/tools/cmd/cover \
	golang.org/x/tools/cmd/stringer

DEV_IMAGE?=consul-k8s-dev
GO_BUILD_TAG?=consul-k8s-build-go
GIT_COMMIT?=$(shell git rev-parse --short HEAD)
GIT_DIRTY?=$(shell test -n "`git status --porcelain`" && echo "+CHANGES" || true)
GIT_DESCRIBE?=$(shell git describe --tags --always)
GIT_IMPORT=github.com/hashicorp/consul-k8s/version
GOLDFLAGS=-X $(GIT_IMPORT).GitCommit=$(GIT_COMMIT)$(GIT_DIRTY) -X $(GIT_IMPORT).GitDescribe=$(GIT_DESCRIBE)

export GIT_COMMIT
export GIT_DIRTY
export GIT_DESCRIBE
export GOLDFLAGS
export GOTAGS



################
# CI Variables #
################
CI_DEV_DOCKER_NAMESPACE?=hashicorpdev
CI_DEV_DOCKER_IMAGE_NAME?=consul-k8s
CI_DEV_DOCKER_WORKDIR?=bin/
CONSUL_K8S_IMAGE_VERSION?=latest
################

DIST_TAG?=1
DIST_BUILD?=1
DIST_SIGN?=1

ifdef DIST_VERSION
DIST_VERSION_ARG=-v "$(DIST_VERSION)"
else
DIST_VERSION_ARG=
endif

ifdef DIST_RELEASE_DATE
DIST_DATE_ARG=-d "$(DIST_RELEASE_DATE)"
else
DIST_DATE_ARG=
endif

ifdef DIST_PRERELEASE
DIST_REL_ARG=-r "$(DIST_PRERELEASE)"
else
DIST_REL_ARG=
endif

PUB_GIT?=1
PUB_WEBSITE?=1

ifeq ($(PUB_GIT),1)
PUB_GIT_ARG=-g
else
PUB_GIT_ARG=
endif

ifeq ($(PUB_WEBSITE),1)
PUB_WEBSITE_ARG=-w
else
PUB_WEBSITE_ARG=
endif

DEV_PUSH?=0
ifeq ($(DEV_PUSH),1)
DEV_PUSH_ARG=
else
DEV_PUSH_ARG=--no-push
endif

all: bin

bin:
	@$(SHELL) $(CURDIR)/build-support/scripts/build-local.sh

dev:
	@$(SHELL) $(CURDIR)/build-support/scripts/build-local.sh -o $(GOOS) -a $(GOARCH)

dev-docker:
	@$(SHELL) $(CURDIR)/build-support/scripts/build-local.sh -o linux -a amd64
	@docker build -t '$(DEV_IMAGE)' --build-arg 'GIT_COMMIT=$(GIT_COMMIT)' --build-arg 'GIT_DIRTY=$(GIT_DIRTY)' --build-arg 'GIT_DESCRIBE=$(GIT_DESCRIBE)' -f $(CURDIR)/build-support/docker/Dev.dockerfile $(CURDIR)

dev-tree:
	@$(SHELL) $(CURDIR)/build-support/scripts/dev.sh $(DEV_PUSH_ARG)

test:
	go test ./...

# requires a consul enterprise binary on the path
ent-test:
	go test ./... -tags=enterprise

cov:
	go test ./... -coverprofile=coverage.out
	go tool cover -html=coverage.out

tools:
	go get -u -v $(GOTOOLS)

# dist builds binaries for all platforms and packages them for distribution
# make dist DIST_VERSION=<Desired Version> DIST_RELEASE_DATE=<release date>
# date is in "month day, year" format.
dist:
	@$(SHELL) $(CURDIR)/build-support/scripts/release.sh -t '$(DIST_TAG)' -b '$(DIST_BUILD)' -S '$(DIST_SIGN)' $(DIST_VERSION_ARG) $(DIST_DATE_ARG) $(DIST_REL_ARG)

publish:
	@$(SHELL) $(CURDIR)/build-support/scripts/publish.sh $(PUB_GIT_ARG) $(PUB_WEBSITE_ARG)

docker-images: go-build-image

go-build-image:
	@echo "Building Golang build container"
	@docker build $(NOCACHE) $(QUIET) --build-arg 'GOTOOLS=$(GOTOOLS)' -t $(GO_BUILD_TAG) - < build-support/docker/Build-Go.dockerfile

clean:
	@rm -rf \
		$(CURDIR)/bin \
		$(CURDIR)/pkg


# In CircleCI, the linux binary will be attached from a previous step at pkg/bin/linux_amd64/. This make target
# should only run in CI and not locally.
ci.dev-docker:
	@echo "Pulling consul-k8s container image - $(CONSUL_K8S_IMAGE_VERSION)"
	@docker pull hashicorp/$(CI_DEV_DOCKER_IMAGE_NAME):$(CONSUL_K8S_IMAGE_VERSION) >/dev/null
	@echo "Building consul-k8s Development container - $(CI_DEV_DOCKER_IMAGE_NAME)"
	@docker build -t '$(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):$(GIT_COMMIT)' \
	--build-arg CONSUL_K8S_IMAGE_VERSION=$(CONSUL_K8S_IMAGE_VERSION) \
	--label COMMIT_SHA=$(CIRCLE_SHA1) \
	--label PULL_REQUEST=$(CIRCLE_PULL_REQUEST) \
	--label CIRCLE_BUILD_URL=$(CIRCLE_BUILD_URL) \
	$(CI_DEV_DOCKER_WORKDIR) -f $(CURDIR)/build-support/docker/Dev.dockerfile
	@echo $(DOCKER_PASS) | docker login -u="$(DOCKER_USER)" --password-stdin
	@echo "Pushing dev image to: https://cloud.docker.com/u/$(CI_DEV_DOCKER_NAMESPACE)/repository/docker/$(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME)"
	@docker push $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):$(GIT_COMMIT)
ifeq ($(CIRCLE_BRANCH), master)
	@docker tag $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):$(GIT_COMMIT) $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):latest
	@docker push $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):latest
endif

.PHONY: all bin clean dev dist docker-images go-build-image test tools ci.dev-docker
