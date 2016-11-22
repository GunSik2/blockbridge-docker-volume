# Copyright (c) 2015-2016, Blockbridge Networks LLC.  All rights reserved.
# Use of this source code is governed by a BSD-style license, found
# in the LICENSE file.

all: volume-driver

volume-driver:
	docker run -e USER=$(shell id -u) --rm -v $(PWD):/usr/src/app blockbridge/volume-driver-build
	docker build -t blockbridge/volume-driver .

plugin: volume-driver
	docker tag blockbridge/volume-driver:latest blockbridge/volume-driver-rootfs:latest
	$(eval ID := $(shell docker create blockbridge/volume-driver-rootfs:latest true))
	sudo rm -rf plugin/rootfs plugin/img.tar
	sudo mkdir -p plugin/rootfs
	docker export "$(ID)" | sudo tar -x -C plugin/rootfs
	sudo mkdir -p plugin/rootfs/var/run/docker/plugins/blockbridge
	cp config.json plugin/.
	sudo docker plugin create blockbridge/volume-driver plugin
	docker rm -vf "$(ID)"
	docker rmi blockbridge/volume-driver-rootfs

bundle:
	rm -f .bundle/config
	docker run -e USER=$(shell id -u) --rm -v $(PWD):/usr/src/app blockbridge/volume-driver-build bash -c 'bundle && bundle update blockbridge-api && bundle update heroics'

nocache:
	docker build --no-cache -t blockbridge/volume-driver .

readme:
	@md-toc-filter README.md.raw > README.md
