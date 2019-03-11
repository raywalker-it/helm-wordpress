SHELL := /bin/bash

REDIS_CHART_VERSION ?= 4.2.7
export REDIS_CHART_VERSION

# Relative path to local chart bucket mirror
CHART_DIRECTORY ?= ../raywalker-helm-charts

# Remote chart bucket GCS bucket
CHART_BUCKET ?= gs://raywalker-helm-charts
CHART_URL ?= https://raywalker-helm-charts.storage.googleapis.com

# Name of current chart
CHART_NAME := $(shell basename "$(PWD)")

# Sed match for replacing build tags with machine-readable characters
SED_MATCH := [^a-zA-Z0-9._-]

# If BUILD_TAG is not set
ifeq ($(strip $(BUILD_TAG)),)
ifeq ($(CIRCLECI),true)
# Configure build variables based on CircleCI environment vars
BUILD_TAG ?= $(shell sed 's/$(SED_MATCH)/-/g' <<< "$(CIRCLE_TAG)")
else
# Not in CircleCI environment, try to set sane defaults
BUILD_TAG ?= $(shell git tag -l --points-at HEAD | tail -n1 | sed 's/$(SED_MATCH)/-/g')
endif
endif

# If BUILD_TAG is blank there's no tag on this commit
ifeq ($(strip $(BUILD_TAG)),)
# Default to branch name - this will lint but not package
BUILD_TAG := testing
endif

.PHONY: all
all: clean rewrite lint dep pull package index push

.PHONY: clean
clean:
	rm -f Chart.yaml requirements.yaml

.PHONY: lint
lint: lint-yaml lint-helm

.PHONY: lint-yaml
lint-yaml: Chart.yaml requirements.yaml
	yamllint .circleci/config.yml
	yamllint Chart.yaml
	yamllint values.yaml
	yamllint requirements.yaml

.PHONY: lint-helm
	@helm lint .

.PHONY: dep
dep: lint
	@helm dependency update

.PHONY: pull
pull:
	@mkdir -p $(CHART_DIRECTORY)
	@pushd $(CHART_DIRECTORY) > /dev/null && \
	gsutil -m rsync -d $(CHART_BUCKET) . && \
	popd > /dev/null

.PHONY: rewrite rewrite-chart rewrite-requirements
rewrite: Chart.yaml requirements.yaml

Chart.yaml:
	BUILD_TAG=$(BUILD_TAG) \
	envsubst < Chart.yaml.in > Chart.yaml

requirements.yaml:
	envsubst < requirements.yaml.in > requirements.yaml

.PHONY: package
package: lint Chart.yaml
	[[ $(BUILD_TAG) =~ ^[0-9]+\.[0-9]+ ]] || { \
		>&2 echo "ERROR: Refusing to package non-semver release: '$(BUILD_TAG)'"; \
		exit 1; \
	}
	@helm package .
	@mv $(CHART_NAME)-*.tgz $(CHART_DIRECTORY)

.PHONY: verify
verify: lint
	@helm verify $(CHART_DIRECTORY)

.PHONY: index
index: lint
	@pushd $(CHART_DIRECTORY) > /dev/null && \
	helm repo index . --url $(CHART_URL) && \
	popd > /dev/null

.PHONY: push
push: package
	@pushd $(CHART_DIRECTORY) > /dev/null && \
	gsutil -m rsync -d . $(CHART_BUCKET) && \
	popd > /dev/null
