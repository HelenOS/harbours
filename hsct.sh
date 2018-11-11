#!/bin/sh

#
# Copyright (c) 2013-2017 Vojtech Horky
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

# Calling harbour functions:
#    These functions are always called in a subshell to "guard" them a little
# bit (variables set by the harbour, cd into package directory).
# 
# Notice on usage of set -o errexit (set -e) 
#    We want to use that option for the harbour scripts to get rid of the
# "|| return 1" at the end of each line.
#    Obvious solution is to wrap the call like this:
#       (  set -o errexit; build ) || { hsct_error "..."; return 1; }
#    This doesn't work because the whole subshell is then part of a ||
# operand and thus the set -e is ignored (even if it is a subshell).
# See https://groups.google.com/d/msg/gnu.bash.bug/NCK_0GmIv2M/y6RQF1AWUQkJ
#    Thus, we need to use the following template to get past this:
#       ( set -o errexit; build; exit $? );
#       [ $? -eq 0 ] || { hsct_error "..."; return 1; }
#
# Also notice that we never ever call exit from the top-most shell when
# leaving after an error. That is to prevent terminating user shell when
# this script is sourced ("env" command). It complicates the error handling
# a bit but it is more reliable than trying to guess whether we are running
# in a subshell or not.
#

HSCT_HOME=`which -- "$0" 2>/dev/null`
# Maybe, we are running Bash
[ -z "$HSCT_HOME" ] && HSCT_HOME=`which -- "$BASH_SOURCE" 2>/dev/null`
HSCT_HOME=`dirname -- "$HSCT_HOME"`
HSCT_HOME=`cd $HSCT_HOME && echo $PWD`
HSCT_HSCT="$HSCT_HOME/hsct.sh"

HSCT_BUILD_DIR=`pwd`/build
HSCT_INCLUDE_DIR=`pwd`/include
HSCT_LIB_DIR=`pwd`/libs
HSCT_DIST_DIR="`pwd`/dist/"
HSCT_ARCHIVE_DIR="`pwd`/archives/"

# Print short help.
# Does not exit the whole script.
hsct_usage() {
	echo "Usage:"
	echo " $1 action [package]"
	echo "    Action can be one of following:"
	echo "       clean     Clean built directory."
	echo "       fetch     Fetch sources (e.g. download from homepage)."
	echo "       build     Build given package."
	echo "       package   Save installable files to allow cleaning."
	echo "       install   Install to uspace/dist of HelenOS."
	echo "       archive   Create tarball instead of installing."
	echo " $1 init [/path/to/HelenOS] [profile]"
	echo "    Initialize current directory as coastline build directory".
	echo "    Full path has to be provided to the HelenOS source tree."
	echo "    If profile is specified, forcefully rebuild to specified profile."
	echo "    If no argument is provided, path to HelenOS source tree is"
	echo "    read from the HELENOS_ROOT environment variable."
	echo " $1 help"
	echo "    Display this help and exit."
}

# Print high-level information message.
hsct_info() {
	echo ">>>" "$@" >&2
}

# Print lower-level information message (additional info after hsct_info).
hsct_info2() {
	echo "     ->" "$@" >&2
}

# Print information message from HARBOUR script.
msg() {
	hsct_info "$@"
}

# Print high-level error message.
hsct_error() {
	echo "[hsct]:" "Error:" "$@" >&2
}

# Print additional details to the error message.
hsct_error2() {
	echo "[hsct]:" "  ->  " "$@" >&2
}

# Run a command but print it first.
hsct_run_echo() {
	echo -n "[hsct]: "
	for ___i in "$@"; do
		echo -n "$___i" | sed -e 's#"#\\"#g' -e 's#.*#"&" #'
	done
	echo
	"$@"
}

# Run comman from HARBOUR script and print it as well.
run() {
	hsct_run_echo "$@"
}

hsct_process_harbour_opts() {
	HSCT_OPTS_NO_DEPENDENCY_BUILDING=false
	HSCT_OPTS_NO_FILE_DOWNLOADING=false
	HSCT_HARBOUR_NAME=""
	
	while [ "$#" -ne 0 ]; do
		case "$1" in
			--no-deps)
				HSCT_OPTS_NO_DEPENDENCY_BUILDING=true
				;;
			--no-fetch)
				HSCT_OPTS_NO_FILE_DOWNLOADING=true
				;;
			--*)
				hsct_error "Unknown option $1."
				return 60
				;;
			*)
				if [ -z "$HSCT_HARBOUR_NAME" ]; then
					HSCT_HARBOUR_NAME="$1"
				else
					hsct_error "Only one package name allowed."
					return 61
				fi
				;;
		esac
		shift
	done
	
	return 0
}

# Fetch all the specified files in the HARBOUR
hsct_fetch() {
	mkdir -p "$HSCT_SOURCES_DIR"
	hsct_info "Fetching sources..."
	for _url in $shipsources; do
		_filename=`basename "$_url"`
		if [ "$_filename" = "$_url" ]; then
			continue
		fi
		if ! [ -r "$HSCT_SOURCES_DIR/$_filename" ]; then
			if $HSCT_OPTS_NO_FILE_DOWNLOADING; then
				hsct_error "File $_filename missing, cannot continue."
				hsct_error2 "Build without --no-fetch."
				return 62
			fi
			
			hsct_info2 "Fetching $_filename..."
			# Remove the file even on Ctrl-C when fetching
			trap "rm -f \"$HSCT_SOURCES_DIR/$_filename\"; echo" SIGINT SIGQUIT
			if ! wget $HSCT_WGET_OPTS "$_url" -O "$HSCT_SOURCES_DIR/$_filename"; then
				rm -f "$HSCT_SOURCES_DIR/$_filename"
				hsct_error "Failed to fetch $_url."
				return 63
			fi
			trap - SIGINT SIGQUIT
		fi
		# TODO - check MD5
	done
	return 0
}

# Remove the build directory of given package.
hsct_clean() {
	hsct_info "Cleaning build directory..."
	rm -rf "$HSCT_BUILD_DIR/$shipname/"*
}

# Build the package.
hsct_build() {
	mkdir -p "$HSCT_BUILD_DIR/$shipname"
	if [ -e "$HSCT_BUILD_DIR/${shipname}.built" ]; then
		hsct_info "No need to build $shipname."
		return 0
	fi
	
	# Check for prerequisities
	for tug in $shiptugs; do
		if ! [ -e "$HSCT_BUILD_DIR/${tug}.packaged" ]; then
			if $HSCT_OPTS_NO_DEPENDENCY_BUILDING; then
				hsct_error "Dependency $tug not built, cannot continue."
				hsct_error2 "Build $tug first or run without --no-deps."
				return 64
			fi
			hsct_info "Need to build $tug first."
			hsct_info2 "Running $HSCT_HSCT package $tug"
			(
				$HSCT_HSCT package $tug
				exit $?
			)
			if [ $? -ne 0 ]; then
				hsct_error "Failed to package dependency $tug."
				hsct_error2 "Cannot continue building $shipname."
				return 65
			fi
			hsct_info2 "Back from building $tug."
		fi
	done
	
	hsct_fetch || return $?
	
	for _url in $shipsources; do
		_filename=`basename "$_url"`
		if [ "$_filename" = "$_url" ]; then
			_origin="$HSCT_HOME/$shipname/$_filename" 
		else
			_origin="$HSCT_SOURCES_DIR/$_filename"
		fi
		ln -srf "$_origin" "$HSCT_BUILD_DIR/$shipname/$_filename"
	done
	
	(
		cd "$HSCT_BUILD_DIR/$shipname/"
		hsct_info "Building..."
		set -o errexit
		build
		exit $?
	)
	if [ $? -ne 0 ]; then
		hsct_error "Build failed!"
		return 66
	fi
	touch "$HSCT_BUILD_DIR/${shipname}.built"
	return 0
}

# Pseudo-installation - copy from build directory to "my" directory, copy libraries
hsct_package() {
	mkdir -p "$HSCT_INCLUDE_DIR" || { hsct_error "Failed to create include directory."; return 67; }
	mkdir -p "$HSCT_LIB_DIR" || { hsct_error "Failed to create library directory."; return 67; }
	mkdir -p "$HSCT_MY_DIR" || { hsct_error "Failed to create package directory."; return 67; }

	if [ -e "$HSCT_BUILD_DIR/${shipname}.packaged" ]; then
		hsct_info "No need to package $shipname."
		return 0;
	fi
	
	hsct_build || return $?
	
	(	
		cd "$HSCT_BUILD_DIR/$shipname/"
		hsct_info "Packaging..."
		set -o errexit
		package
		exit $?
	)
	if [ $? -ne 0 ]; then
		hsct_error "Packaging failed!"
		return 68
	fi
	touch "$HSCT_BUILD_DIR/${shipname}.packaged"
	return 0
}

# Install the package to HelenOS source tree (to uspace/overlay).
hsct_install() {
	hsct_package || return $?

	hsct_info "Installing..."
	if ls "$HSCT_MY_DIR"/* &>/dev/null; then
		mkdir -p "$HSCT_OVERLAY"
		cp -v -r -L "$HSCT_MY_DIR"/* "$HSCT_OVERLAY" || return 69
		hsct_info2 "Do not forget to rebuild the image."
	else
		hsct_info2 "Note: nothing to install."
	fi
	return 0
}

# Create tarball to allow redistribution of the build packages
hsct_archive() {
	hsct_package || return $?
	
	hsct_info "Creating the archive..."
	mkdir -p "$HSCT_ARCHIVE_DIR"
	(
		set -o errexit
		cd "$HSCT_DIST_DIR/$shipname"
		case "$HSCT_FORMAT" in
			tar.gz)
				tar czf "$HSCT_ARCHIVE_DIR/$shipname.tar.gz" .
				;;
			tar.xz)
				tar cJf "$HSCT_ARCHIVE_DIR/$shipname.tar.xz" .
				;;
			*)
				hsct_info "Unknown archive_format $HSCT_FORMAT."
				exit 71
				;;
		esac
	)
	if [ $? -ne 0 ]; then
		hsct_error "Archiving failed!"
		return 72
	fi
	
	return 0
}

hsct_load_config() {
	# Defaults
	HSCT_CONFIG="./config.sh"
	HSCT_WGET_OPTS=
	HSCT_SOURCES_DIR=`pwd`/sources
	HSCT_FORMAT="tar.xz"
	HSCT_PARALLELISM=`nproc`
	HELENOS_ROOT=

	if [ -e "$HSCT_CONFIG" ]; then
		. $HSCT_CONFIG
	fi

	HELENOS_EXPORT_ROOT="$HELENOS_ROOT/uspace/export"
	HELENOS_CONFIG="$HELENOS_EXPORT_ROOT/config.rc"
}

hsct_save_config() {
	echo "HSCT_WGET_OPTS=\"${HSCT_WGET_OPTS}\"" >> "${HSCT_CONFIG}.new"
	echo "HSCT_SOURCES_DIR=\"${HSCT_SOURCES_DIR}\"" >> "${HSCT_CONFIG}.new"
	echo "HSCT_FORMAT=\"${HSCT_FORMAT}\"" >> "${HSCT_CONFIG}.new"
	echo "HSCT_PARALLELISM=\"${HSCT_PARALLELISM}\"" >> "${HSCT_CONFIG}.new"
	echo "HELENOS_ROOT=\"${HELENOS_ROOT}\"" >> "${HSCT_CONFIG}.new"
	mv "${HSCT_CONFIG}.new" "${HSCT_CONFIG}"
}

# Initialize current directory for coastline building.
hsct_init() {
	hsct_load_config

	_root_dir=$1
	profile=$2

	if [ -z "$_root_dir" ]; then
		# Try to get HELENOS_ROOT from the environment if not specified.
		_root_dir="$HELENOS_ROOT"
	fi

	if [ -z "$_root_dir" ]; then
		hsct_error "HELENOS_ROOT is not set. Either set the environment variable, or specify it on the command line.";
		return 73
	fi
	
	_root_dir=`( cd "$_root_dir"; pwd ) 2>/dev/null`
	if ! [ -e "$_root_dir/HelenOS.config" ]; then
		hsct_error "$_root_dir does not look like a valid HelenOS directory.";
		return 74
	fi
	
	HELENOS_ROOT="$_root_dir"
	HELENOS_EXPORT_ROOT="$HELENOS_ROOT/uspace/export"
	HELENOS_CONFIG="$HELENOS_EXPORT_ROOT/config.rc"

	hsct_info "Initializing this build directory."
	(
		EXPORT_DIR=`pwd`/helenos
		set -o errexit
		cd "$HELENOS_ROOT"
		if [ -z $profile ]; then
			hsct_info2 "Reusing existing configuration."
			make -j`nproc` export-cross HANDS_OFF=y >/dev/null 2>&1
		else
			hsct_info2 "Cleaning previous configuration in $PWD."
			make distclean >/dev/null 2>&1
			hsct_info2 "Configuring for $profile."
			make -j`nproc` export-cross "PROFILE=$profile" HANDS_OFF=y >/dev/null 2>&1
		fi
	)
	if [ $? -ne 0 ]; then
		hsct_error "Failed to automatically configure HelenOS for profile '$profile'."
		return 75
	fi
	
	hsct_info "Creating facade toolchain."
	mkdir -p facade
	facade_path="$PWD/facade"

	(
		. "$HELENOS_CONFIG"

		if [ -z "$HELENOS_ARCH" ]; then
			hsct_error "HELENOS_ARCH undefined."
			return 76
		fi

		cd $HSCT_HOME/facade/src
		for x in *; do
			install -m 755 "$x" "$facade_path/$HELENOS_ARCH-helenos-$x"
		done
	)

	if [ $? -ne 0 ]; then
		hsct_error "Failed to create toolchain facade for profile '$profile'."
		return 77
	fi

	hsct_save_config

	return 0
}

alias leave_script_ok='return 0 2>/dev/null || exit 0'
alias leave_script_err='return 1 2>/dev/null || exit 1'

hsct_print_vars() {
	# This is separate from the rest, so that the user can run
	# eval `path/to/hsct.sh vars` to get these vars in interactive shell.

	hsct_load_config

	if ! [ -e "$HELENOS_CONFIG" ]; then
		hsct_error "Configuration not found. Maybe you need to run init first?"
		return 78
	fi

	. $HELENOS_CONFIG

	echo "export HELENOS_EXPORT_ROOT='$HELENOS_EXPORT_ROOT'"
	echo "export HSCT_REAL_CC='$HELENOS_TARGET-gcc'"
	echo "export HSCT_REAL_CXX='$HELENOS_TARGET-g++'"

	echo "export HSCT_ARFLAGS='$HELENOS_ARFLAGS'"
	echo "export HSCT_CPPFLAGS='-isystem $HSCT_INCLUDE_DIR $HELENOS_CPPFLAGS'"
	echo "export HSCT_CFLAGS='$HELENOS_CFLAGS'"
	echo "export HSCT_CXXFLAGS='$HELENOS_CXXFLAGS'"
	echo "export HSCT_ASFLAGS='$HELENOS_ASFLAGS'"
	echo "export HSCT_LDFLAGS='-L $HSCT_LIB_DIR $HELENOS_LDFLAGS'"
	echo "export HSCT_LDLIBS='$HELENOS_LDLIBS'"

	target="$HELENOS_ARCH-helenos"
	cctarget="$HELENOS_ARCH-linux-gnu"
	cvars="CC=$target-cc CXX=$target-cxx AR=$target-ar AS=$target-as CPP=$target-cpp NM=$target-nm OBJDUMP=$target-objdump OBJCOPY=$target-objcopy STRIP=$target-strip RANLIB=$target-ranlib"
	
	echo "export HSCT_CC='$target-cc'"
	echo "export HSCT_CXX='$target-cxx'"
	echo "export HSCT_TARGET='$target'"
	echo "export HSCT_REAL_TARGET='$HELENOS_TARGET'"
	# Target to set for cross-compiled cross-compilers.
	echo "export HSCT_CCROSS_TARGET='$cctarget'"
	echo "export HSCT_CONFIGURE_VARS='$cvars'"
	echo "export HSCT_CONFIGURE_ARGS='--build=`sh $HSCT_HOME/config.guess` --host=$target $cvars'"

	echo "export HELENOS_CROSS_PATH=$HELENOS_CROSS_PATH"
	echo "export PATH='$PWD/facade:$HELENOS_CROSS_PATH:$PATH'"
}

hsct_pkg() {
	hsct_load_config
	eval `hsct_print_vars`

	if [ -z "$HELENOS_EXPORT_ROOT" ]; then
		case "$HSCT_ACTION" in
		clean|fetch)
			;;
		*)
			return 79
			;;
		esac
	fi

	HSCT_MY_DIR="$HSCT_DIST_DIR/$HSCT_HARBOUR_NAME"
	HSCT_OVERLAY="$HELENOS_ROOT/uspace/overlay"
	HSCT_CONFIG_SUB="$HSCT_HOME/config.sub"

	if ! [ "$HSCT_PARALLELISM" -ge 0 ] 2>/dev/null; then
		HSCT_PARALLELISM="1"
	fi

	if ! [ -d "$HSCT_HOME/$HSCT_HARBOUR_NAME" ]; then
		hsct_error "Unknown package $HSCT_HARBOUR_NAME."
		leave_script_err
	fi

	if ! [ -r "$HSCT_HOME/$HSCT_HARBOUR_NAME/HARBOUR" ]; then
		hsct_error "HARBOUR file missing." >&2
		leave_script_err
	fi

	# Source the harbour to get access to the variables and functions
	. "$HSCT_HOME/$HSCT_HARBOUR_NAME/HARBOUR"

	if [ "$shipfunnels" -ne "1" ] 2>/dev/null; then
		shipfunnels="$HSCT_PARALLELISM"
	fi

	case "$HSCT_ACTION" in
		clean)
			hsct_clean
			;;
		fetch)
			hsct_fetch
			;;
		build)
			hsct_build
			;;
		package)
			hsct_package
			;;
		install)
			hsct_install
			;;
		archive)
			hsct_archive
			;;
		*)
			hsct_error "Internal error, we shall not get to this point!"
			leave_script_err
			;;
	esac

	return $?
}

HSCT_ACTION="$1"

case "$HSCT_ACTION" in
	clean|fetch|build|package|install|archive)
		shift
		if ! hsct_process_harbour_opts "$@"; then
			leave_script_err
		fi
		if [ -z "$HSCT_HARBOUR_NAME" ]; then
			hsct_usage "$0"
			leave_script_err
		fi
		hsct_pkg
		exit $?
		;;
	vars)
		hsct_print_vars
		exit $?
		;;
	init)
		hsct_init "$2" "$3" "$4"
		exit $?
		;;
	help|--help|-h|-?)
		hsct_usage "$0"
		leave_script_ok
		;;
	*)
		hsct_usage "$0"
		leave_script_err
		;;
esac

