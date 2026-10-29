ENGINE ?= podman
IMAGE ?= localhost/renkuos-bootstrap-python312:nightly-mmc
WORKDIR ?= $(HOME)/haiku-nightly-mmc-work
TARGET_ARCH ?= arm64
RESUME ?= 0
BUILD_DRIVER_REV ?= $(shell git rev-parse --verify HEAD 2>/dev/null || echo unversioned)

.PHONY: check-build-files image prep crosstools bootstrap build-cross-fortran nightly-mmc enter clean-work

check-build-files:
	@test -z "$$(git status --porcelain -- .)" || { echo "Commit or discard changes under 3rdparty/docker/bootstrap before building." >&2; exit 1; }

image: check-build-files
	$(ENGINE) build . -t $(IMAGE)

prep: image
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -v "$(WORKDIR):/work:exec" $(IMAGE) prep

crosstools: image
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) crosstools

bootstrap: image
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) bootstrap

build-cross-fortran: image
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) build-cross-fortran

nightly-mmc: image
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -e RESUME=$(RESUME) -e BUILD_DRIVER_REV=$(BUILD_DRIVER_REV) -v "$(WORKDIR):/work:exec" $(IMAGE) nightly-mmc

enter: image
	$(ENGINE) run --rm -it -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) /bin/bash -l

# This removes source checkouts, intermediate builds, and generated images.
clean-work:
	test -n "$(WORKDIR)" && test "$(WORKDIR)" != "/" && rm -rf "$(WORKDIR)"
