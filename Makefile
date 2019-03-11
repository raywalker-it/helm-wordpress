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

# Trim any leading v from semver string
BUILD_TAG := $(shell echo $(BUILD_TAG) | sed 's/^v//')

# If BUILD_TAG is blank there's no tag on this commit
ifeq ($(strip $(BUILD_TAG)),)
# Default to branch name - this will lint but not package
BUILD_TAG := testing
endif

export BUILD_TAG

.PHONY: all
all: clean lint dep pull package index push

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
lint-helm: Chart.yaml requirements.yaml
	@helm lint .

.PHONY: dep
dep: lint
	@helm dependency update

.PHONY: pull
pull:
	@mkdir -p $(CHART_DIRECTORY)
	gsutil -m rsync -d $(CHART_BUCKET) $(CHART_DIRECTORY)

Chart.yaml:
	envsubst < Chart.yaml.in > Chart.yaml

requirements.yaml:
	envsubst < requirements.yaml.in > requirements.yaml

.PHONY: package
package: lint Chart.yaml
	@[[ $(BUILD_TAG) =~ ^[0-9]+\.[0-9]+ ]] || { \
	 >&2 echo "ERROR: Refusing to package non-semver release: '$(BUILD_TAG)')" && \
	 exit 1; \
	}
	@helm package .
	@mv $(CHART_NAME)-*.tgz $(CHART_DIRECTORY)

.PHONY: verify
verify: lint
	@helm verify $(CHART_DIRECTORY)

.PHONY: index
index: lint
	helm repo index $(CHART_DIRECTORY) --url $(CHART_URL)

.PHONY: push
push: package
	gsutil -m rsync -d $(CHART_DIRECTORY) $(CHART_BUCKET)
