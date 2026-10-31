ENGINE ?= podman
IMAGE ?= localhost/renkuos-bootstrap-python312:nightly-mmc
WORKDIR ?= $(HOME)/haiku-nightly-mmc-work
TARGET_ARCH ?= arm64
RESUME ?= 0
HAIKU_RESUME_BUILD ?= 0
BUILD_DRIVER_REV ?= $(shell git rev-parse --verify HEAD 2>/dev/null || echo unversioned)

.PHONY: check-build-files image mark-workdir prep crosstools bootstrap build-cross-fortran nightly-mmc enter clean-work

check-build-files:
	@test -z "$$(git status --porcelain -- .)" || { echo "Commit or discard changes under 3rdparty/docker/bootstrap before building." >&2; exit 1; }

image: check-build-files
	$(ENGINE) build . -t $(IMAGE)

mark-workdir:
	@workdir="$(abspath $(WORKDIR))"; \
	  home="$(abspath $(HOME))"; \
	  marker="$$workdir/.renkuos-haiku-nightly-mmc-workspace"; \
	  if [ "$$workdir" = "/" ] || [ "$$workdir" = "$$home" ] || [ -L "$$workdir" ] || [ -L "$$marker" ]; then \
	    echo "Refusing unsafe WORKDIR: $$workdir" >&2; exit 1; \
	  elif [ -f "$$marker" ]; then \
	    test "$$(cat "$$marker")" = "RenkuOS ARM64 nightly-mmc workspace v1" || { echo "Invalid workspace marker: $$marker" >&2; exit 1; }; \
	  elif [ -d "$$workdir/src/haiku" ] && [ -d "$$workdir/generated.arm64" ] && [ -f "$$workdir/src/haiku/build/jam/DefaultBuildProfiles" ]; then \
	    printf '%s\n' "RenkuOS ARM64 nightly-mmc workspace v1" > "$$marker"; \
	  elif [ -d "$$workdir" ] && [ -n "$$(find "$$workdir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then \
	    echo "Refusing to use a non-empty unmarked WORKDIR: $$workdir" >&2; exit 1; \
	  else \
	    mkdir -p "$$workdir"; printf '%s\n' "RenkuOS ARM64 nightly-mmc workspace v1" > "$$marker"; \
	  fi

prep: image mark-workdir
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -v "$(WORKDIR):/work:exec" $(IMAGE) prep

crosstools: image mark-workdir
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) crosstools

bootstrap: image mark-workdir
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) bootstrap

build-cross-fortran: image mark-workdir
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) build-cross-fortran

nightly-mmc: image mark-workdir
	mkdir -p "$(WORKDIR)"
	$(ENGINE) run --rm -e TARGET_ARCH=$(TARGET_ARCH) -e RESUME=$(RESUME) -e HAIKU_RESUME_BUILD=$(HAIKU_RESUME_BUILD) -e BUILD_DRIVER_REV=$(BUILD_DRIVER_REV) -v "$(WORKDIR):/work:exec" $(IMAGE) nightly-mmc

enter: image mark-workdir
	$(ENGINE) run --rm -it -e TARGET_ARCH=$(TARGET_ARCH) -v "$(WORKDIR):/work:exec" $(IMAGE) /bin/bash -l

# This removes only a workspace created by these Makefile targets.
clean-work:
	@workdir="$(abspath $(WORKDIR))"; \
	  home="$(abspath $(HOME))"; \
	  marker="$$workdir/.renkuos-haiku-nightly-mmc-workspace"; \
	  if [ "$$workdir" = "/" ] || [ "$$workdir" = "$$home" ] || [ -L "$$workdir" ] || [ -L "$$marker" ] || [ ! -f "$$marker" ] || [ "$$(cat "$$marker")" != "RenkuOS ARM64 nightly-mmc workspace v1" ]; then \
	    echo "Refusing to remove unmarked or unsafe WORKDIR: $$workdir" >&2; exit 1; \
	  fi; \
	  rm -rf -- "$$workdir"
