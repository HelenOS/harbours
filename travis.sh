#!/bin/sh

#
# Copyright (c) 2018 Vojtech Horky
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# - Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
# - The name of the author may not be used to endorse or promote products
#   derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

#
# This is wrapper script for testing build of HelenOS harbours under
# Travis CI [1].
#
# You probably do not want to run this script directly. If you wish to test
# that HelenOS harbours builds for all architectures, consider using either
# our CI solution [2].
#
# [1] https://travis-ci.org/
# [2] http://www.helenos.org/wiki/CI
#


H_ARCH_CONFIG_CROSS_TARGET=2

h_get_arch_config_space() {
    cat <<'EOF_CONFIG_SPACE'
amd64:amd64-unknown-elf
arm32/beagleboardxm:arm-linux-gnueabi
arm32/beaglebone:arm-linux-gnueabi
arm32/gta02:arm-linux-gnueabi
arm32/integratorcp:arm-linux-gnueabi
arm32/raspberrypi:arm-linux-gnueabi
ia32:i686-pc-linux-gnu
ia64/i460GX:ia64-pc-linux-gnu
ia64/ski:ia64-pc-linux-gnu
mips32/malta-be:mips-linux-gnu
mips32/malta-le:mipsel-linux-gnu
mips32/msim:mipsel-linux-gnu
ppc32:ppc-linux-gnu
sparc64/niagara:sparc64-linux-gnu
sparc64/ultra:sparc64-linux-gnu
EOF_CONFIG_SPACE
}

h_get_arch_config() {
    h_get_arch_config_space | grep "^$H_ARCH:" | cut '-d:' -f "$1"
}



#
# main script starts here
#

# Check we are actually running inside Travis
if [ -z "$TRAVIS" ]; then
    echo "\$TRAVIS env not set. Are you running me inside Travis?" >&2
    exit 5
fi

# Check HelenOS configuration was set-up
if [ -z "$H_ARCH" ]; then
    echo "\$H_ARCH env not set. Are you running me inside Travis?" >&2
    exit 5
fi

# Check HARBOUR was definied
if [ -z "$H_HARBOUR" ]; then
    echo "\$H_HARBOUR env not set. Are you running me inside Travis?" >&2
    exit 5
fi

# Check cross-compiler target
H_CROSS_TARGET=`h_get_arch_config $H_ARCH_CONFIG_CROSS_TARGET`
if [ -z "$H_CROSS_TARGET" ]; then
    echo "No suitable cross-target found for '$H_ARCH.'" >&2
    exit 1
fi


# Custom CROSS_PREFIX
export CROSS_PREFIX=/usr/local/cross-static/


# Default HelenOS repository
if [ -z "$H_HELENOS_REPOSITORY" ]; then
    H_HELENOS_REPOSITORY="https://github.com/HelenOS/helenos.git"
fi

if [ "$1" = "help" ]; then
    echo
    echo "Following variables needs to be set prior running this script."
    echo "Example settings follows:"
    echo
    echo "export H_ARCH=$H_ARCH"
    echo "export H_ARCH=$H_HARBOUR"
    echo "export TRAVIS_BUILD_ID=`date +%s`"
    echo
    exit 0

elif [ "$1" = "install" ]; then
    set -x
    
    # Install dependencies
    sudo apt-get -qq update || exit 1
    sudo apt-get install -y genisoimage || exit 1

    # Fetch and install cross-compiler
    wget "http://ci.helenos.org/download/helenos-cross-$H_CROSS_TARGET.static.tar.xz" -O "/tmp/cross-$H_CROSS_TARGET.static.tar.xz" || exit 1
    sudo mkdir -p "$CROSS_PREFIX" || exit 1
    sudo tar -xJ -C "$CROSS_PREFIX" -f "/tmp/cross-$H_CROSS_TARGET.static.tar.xz" || exit 1
    exit 0


elif [ "$1" = "run" ]; then
    set -x
    
    H_HARBOURS_HOME=`pwd`
    
    cd "$HOME" || exit 1
    
    git clone --depth 10 "$H_HELENOS_REPOSITORY" helenos || exit 1
    
    mkdir "build-$TRAVIS_BUILD_ID" || exit 1

	cd "build-$TRAVIS_BUILD_ID" || exit 1
	
	git clone "$HOME/helenos" helenos || exit 1
	
	(
	   cd helenos
	   make "PROFILE=$H_ARCH" HANDS_OFF=y >build.log 2>&1
	   RET="$?"
	   tail -n 20 "build.log"
	   exit $RET
	) || exit 1
	        

	mkdir build || exit 1
	cd build || exit 1
	
	"$H_HARBOURS_HOME/hsct.sh" init "$HOME/build-$TRAVIS_BUILD_ID/helenos" || exit 1

    # We cannot flood the output as Travis has limit of maximum output size
    # (reason is to prevent endless stacktraces going forever). But also Travis
    # kills a job that does not print anything for a while.
    #
    # So we store the full output into a file but print every 10th line.
    # As pipe tends to hide errors we check the success by checking that archive
    # exists.
    #
    "$H_HARBOURS_HOME/hsct.sh" archive "$H_HARBOUR" 2>&1 | tee build.log | awk '!(NR%10)'
    
    tail -n 1000 build.log
    
    test -s "archives/$H_HARBOUR.tar.xz"
    
    RET="$?"
    if [ $RET -ne 0 ]; then
        exit $RET
    fi
    
    ls -lh archives
    
    set +x
    
    echo "Looks good, $H_HARBOUR built on $H_ARCH."
    echo
else
    echo "Invalid action specified." >&2
    exit 5
fi
