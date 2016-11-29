#!/bin/bash
###########################################################
# Copyright (c) 2015-2016, Blockbridge Networks LLC.  All rights reserved.
# Use of this source code is governed by a BSD-style license, found
# in the LICENSE file.
###########################################################

###########################################################
# Blockbridge docker volume driver entrypoint
###########################################################

# trap signals
trap '' TERM

# setup environment
export RUBYLIB=/usr/lib/blockbridge-ruby:/usr/lib/blockbridge-ruby/lib/ruby/2.3.0:/usr/lib/blockbridge-ruby/lib/ruby/2.3.0/x86_64-linux
export PATH=/usr/lib/blockbridge-ruby/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/bb/bin:/usr/lib/blockbridge-ruby/bin:/usr/src/app/exe

# run blockbridge docker volume driver
ROOTDIR=$(dirname $0)
mkdir -p /run/docker/plugins/blockbridge
ruby -rbundler/setup $ROOTDIR/volume_driver.rb -e production -S /run/docker/plugins/blockbridge/blockbridge.sock
