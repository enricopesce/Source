ENGINE ?= podman
IMAGE ?= localhost/renkuos-bootstrap-python312:nightly-mmc
WORKDIR ?= $(HOME)/haiku-nightly-mmc-work
TARGET_ARCH ?= arm64
RESUME ?= 0

.PHONY: image prep crosstools bootstrap nightly-mmc enter clean-work

image:
	$(ENGINE) build . -t $(IMAGE)

prep: image
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -v "$(WORKDIR):/work:exec" $(IMAGE) prep

crosstools: image
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) crosstools

bootstrap: image
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) bootstrap

nightly-mmc: image
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -e RESUME=$(RESUME) -v "$(WORKDIR):/work:exec" $(IMAGE) nightly-mmc

enter: image
	$(ENGINE) run --rm -it -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) /bin/bash -l

# This removes source checkouts, intermediate builds, and generated images.
clean-work:
	test -n "$(WORKDIR)" && test "$(WORKDIR)" != "/" && rm -rf "$(WORKDIR)"
