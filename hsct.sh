#!/bin/sh

#
# Copyright (c) 2013 Vojtech Horky
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
#       (  set -o errexit; build ) || hsct_fatal "Build failed"
#    This doesn't work because the whole subshell is then part of a ||
# operand and thus the set -e is ignored (even if it is a subshell).
# See https://groups.google.com/d/msg/gnu.bash.bug/NCK_0GmIv2M/y6RQF1AWUQkJ
#    Thus, we need to use the following template to get past this:
#       ( set -o errexit; build; exit $? ); [ $? -eq 0 ] || hsct_fatal "..."
#

HSCT_HOME=`which -- "$0" 2>/dev/null`
# Maybe, we are running Bash
[ -z "$HSCT_HOME" ] && HSCT_HOME=`which -- "$BASH_SOURCE" 2>/dev/null`
HSCT_HOME=`dirname -- "$HSCT_HOME"`

HSCT_SOURCES_DIR=`pwd`/sources
HSCT_BUILD_DIR=`pwd`/build
HSCT_INCLUDE_DIR=`pwd`/include
HSCT_LIB_DIR=`pwd`/libs
HSCT_MISC_DIR=`pwd`/misc
HSCT_APPS_DIR=`pwd`/apps
HSCT_DISABLED_CFLAGS="-Werror -Werror-implicit-function-declaration"
HSCT_SHOW_EXPORTS=false

hsct_usage() {
	echo "$1 action [package]"
	echo "action can be one of following:"
	echo "   clean     Clean built directory."
	echo "   build     Build given package."
	echo "   package   Save installable files to allow cleaning."
	echo "   install   Install to uspace/dist of HelenOS."
	echo "   uninstall Try to remove what was installed to uspace/dist."
}

hsct_info() {
	echo ">>>" "$@" >&2
}

hsct_info2() {
	echo "     ->" "$@" >&2
}

msg() {
	hsct_info "$@"
}

hsct_error() {
	echo "[hsct]:" "Error:" "$@" >&2
}

hsct_run_echo() {
	echo "[hsct]:" "$@"
	"$@"
}

run() {
	hsct_run_echo "$@"
}

# hsct_get_config CONFIG_FILE variable
hsct_get_config() {
	grep '^[ \t]*'"$2" "$1" | cut '-d=' -f 2 | \
		sed -e 's/^[ \t]*//' -e 's/[ \t]*$//'
}

hsct_fetch() {
	mkdir -p "$HSCT_SOURCES_DIR"
	hsct_info "Fetching sources..."
	for _url in $shipsources; do
		_filename=`basename "$_url"`
		if [ "$_filename" = "$_url" ]; then
			continue
		fi
		if ! [ -r "$HSCT_SOURCES_DIR/$_filename" ]; then
			hsct_info2 "Fetching $_filename..."
			if ! wget "$_url" -O "$HSCT_SOURCES_DIR/$_filename"; then
				rm -f "$HSCT_SOURCES_DIR/$_filename"
				hsct_error "Failed to fetch $_url."
				return 1
			fi
		fi
		# TODO - check MD5
	done
	return 0
}


# get_var_from_makefile CC Makefile.common
hsct_get_var_from_makefile() {
	# echo "make -C `dirname "$2"` -f - -s __armagedon_" >&2
	(
		echo "$3"
		echo "$4"
		echo "$5"
		echo "__genesis__:"
		echo
		echo "CONFIG_DEBUG=n"
		echo include `basename "$2"`
		echo "CONFIG_DEBUG=n"
		echo
		echo "__armagedon__:"
		echo "	echo \$($1)"
		echo
	)  | make -C `dirname "$2"` -f - -s __armagedon__
}

hsct_get_var_from_uspace() {
	if [ -z "$2" ]; then
		hsct_get_var_from_makefile "$1" "$HSCT_HELENOS_ROOT/uspace/Makefile.common" "USPACE_PREFIX=$HSCT_HELENOS_ROOT/uspace"
	else
		hsct_get_var_from_makefile "$1" "$HSCT_HELENOS_ROOT/uspace/$2" "USPACE_PREFIX=$HSCT_HELENOS_ROOT/uspace" "$3" "$4"
	fi
}

hsct_harbour_export() {
	export "$1"
	_varname=`echo "$1" | sed 's/=.*//'`
	if $HSCT_SHOW_EXPORTS; then
		eval echo "$_varname=\$$_varname" | sed -e 's#"#\\"#g' -e 's#\\#\\\\#g' \
				-e 's#=\(.*\)#="\1"#' >&2
	fi
	return 0 
}

hsct_prepare_env_build() {
	hsct_info "Obtaining CC, CFLAGS etc."
	hsct_harbour_export HSCT_CC=`hsct_get_var_from_uspace CC`
	hsct_harbour_export HSCT_AS=`hsct_get_var_from_uspace AS`
	hsct_harbour_export HSCT_LD=`hsct_get_var_from_uspace LD`
	hsct_harbour_export HSCT_AR=`hsct_get_var_from_uspace AR`
	hsct_harbour_export HSCT_STRIP=`hsct_get_var_from_uspace STRIP`
	hsct_harbour_export HSCT_OBJCOPY=`hsct_get_var_from_uspace OBJCOPY`
	hsct_harbour_export HSCT_OBJDUMP=`hsct_get_var_from_uspace OBJDUMP`
	# HelenOS do not use ranlib or nm but some applications require it
	hsct_harbour_export HSCT_RANLIB=`echo "$HSCT_AR" | sed 's/-ar$/-ranlib/'`
	hsct_harbour_export HSCT_NM=`echo "$HSCT_AR" | sed 's/-ar$/-nm/'`

	# Get the flags
	_CFLAGS=`hsct_get_var_from_uspace CFLAGS`
	_LDFLAGS=`hsct_get_var_from_uspace LFLAGS`
	_LINKER_SCRIPT=`hsct_get_var_from_uspace LINKER_SCRIPT`
	
	# Get rid of the disabled CFLAGS
	_CFLAGS_OLD="$_CFLAGS"
	_CFLAGS=""
	for _flag in $_CFLAGS_OLD; do
		_disabled=false
		for _disabled_flag in $HSCT_DISABLED_CFLAGS; do
			if [ "$_disabled_flag" = "$_flag" ]; then
				_disabled=true
				break
			fi
		done
		if ! $_disabled; then
			_CFLAGS="$_CFLAGS $_flag"
		fi
	done
	
	
	
	_POSIX_LIB="$HSCT_HELENOS_ROOT/uspace/lib/posix"
	# Include paths
	_POSIX_INCLUDES="-I$_POSIX_LIB/include/posix -I$_POSIX_LIB/include"
	# Paths to libraries
	_POSIX_LIBS_LFLAGS="-L$_POSIX_LIB -L$HSCT_HELENOS_ROOT/uspace/lib/softint -L$HSCT_HELENOS_ROOT/uspace/lib/softfloat"
	# Actually used libraries
	# The --whole-archive is used to allow correct linking of static libraries
	# (otherwise, the ordering is crucial and we usally cannot change that in the
	# application Makefiles).
	_POSIX_LINK_LFLAGS="--whole-archive --start-group -lposixaslibc -lsoftint --end-group --no-whole-archive -lc4posix"
	_POSIX_BASE_LFLAGS="-n -T $_LINKER_SCRIPT"


	# Update LDFLAGS
	_LDFLAGS="$_LDFLAGS $_POSIX_LIBS_LFLAGS $_POSIX_LINK_LFLAGS $_POSIX_BASE_LFLAGS"

	# The LDFLAGS might be used through CC, thus prefixing with -Wl is required
	_LDFLAGS_FOR_CC=""
	for _flag in $_LDFLAGS; do
		_LDFLAGS_FOR_CC="$_LDFLAGS_FOR_CC -Wl,$_flag"
	done
	
	# Update the CFLAGS
	hsct_harbour_export HSCT_CFLAGS="$_POSIX_INCLUDES $_CFLAGS"
	hsct_harbour_export HSCT_LDFLAGS_FOR_CC="$_LDFLAGS_FOR_CC"
	hsct_harbour_export HSCT_LDFLAGS="$_LDFLAGS"
	
	# Target architecture
	_UARCH=`hsct_get_var_from_uspace UARCH`
	_TARGET=""
	case $_UARCH in
		ia32)
			_TARGET="i686-pc-linux-gnu"
			;;
		amd64)
			_TARGET="amd64-linux-gnu"
			;;
		mips32)
			_TARGET="mipsel-linux-gnu"
			;;
		*)
			hsct_error 'Unsupported architecture: $(UARCH) =' "'$_UARCH'."
			return 1
			;;
	esac
	hsct_harbour_export HSCT_GNU_TARGET="$_TARGET"
	return 0
}

hsct_prepare_env_package() {
	hsct_harbour_export HSCT_INCLUDE_DIR
	hsct_harbour_export HSCT_LIB_DIR
	hsct_harbour_export HSCT_MISC_DIR
	hsct_harbour_export HSCT_APPS_DIR
	return 0
}

hsct_clean() {
	hsct_info "Cleaning build directory..."
	rm -rf "$HSCT_BUILD_DIR/$shipname/"*
}

hsct_build() {
	mkdir -p "$HSCT_BUILD_DIR/$shipname"
	if [ -e "$HSCT_BUILD_DIR/${shipname}.built" ]; then
		hsct_info "No need to build $shipname."
		return 0
	fi
	
	hsct_fetch || return 1
	
	for _url in $shipsources; do
		_filename=`basename "$_url"`
		if [ "$_filename" = "$_url" ]; then
			_origin="$HSCT_HOME/$shipname/$_filename" 
		else
			_origin="$HSCT_SOURCES_DIR/$_filename"
		fi
		ln -sf "$_origin" "$HSCT_BUILD_DIR/$shipname/$_filename"
	done
	
	hsct_prepare_env_build || return 1
	
	(
		cd "$HSCT_BUILD_DIR/$shipname/"
		hsct_info "Building..."
		set -o errexit
		build
		exit $?
	)
	if [ $? -ne 0 ]; then
		hsct_error "Build failed!"
		return 1
	fi
	touch "$HSCT_BUILD_DIR/${shipname}.built"
	return 0
}

hsct_package() {
	mkdir -p "$HSCT_INCLUDE_DIR" || hsct_fatal "Failed to create include directory."
	mkdir -p "$HSCT_LIB_DIR" || hsct_fatal "Failed to create library directory."
	mkdir -p "$HSCT_MISC_DIR" || hsct_fatal "Failed to create miscellaneous directory."
	mkdir -p "$HSCT_APPS_DIR" || hsct_fatal "Failed to create apps directory."
	
	if [ -e "$HSCT_BUILD_DIR/${shipname}.packaged" ]; then
		hsct_info "No need to package $shipname."
		return 0;
	fi
	
	hsct_build || return 1
	
	hsct_prepare_env_package || return 1
	
	(	
		cd "$HSCT_BUILD_DIR/$shipname/"
		hsct_info "Packaging..."
		set -o errexit
		package
		exit $?
	)
	if [ $? -ne 0 ]; then
		hsct_error "Packaging failed!"
		return 1
	fi
	touch "$HSCT_BUILD_DIR/${shipname}.packaged"
	return 0
}

hsct_install() {
	hsct_package || return 1

	hsct_prepare_env_package || return 1
	
	(	
		hsct_info "Installing..."
		set -o errexit
		dist
		exit $?
	)
	if [ $? -ne 0 ]; then
		hsct_error "Installing failed!"
		return 1
	fi
	return 0
}

hsct_uninstall() {
	hsct_prepare_env_package || return 0

	(
		hsct_info "Uninstalling..."
		set -o errexit
		undist
		exit $?
	)
	if [ $? -ne 0 ]; then
		hsct_error "Uninstalling failed!"
		return 1
	fi
	return 0
}

alias leave_script_ok='return 0 2>/dev/null || exit 0'
alias leave_script_err='return 1 2>/dev/null || exit 1'

HSCT_CONFIG=hsct.conf
HSCT_HELENOS_ROOT=`hsct_get_config "$HSCT_CONFIG" root`
if [ -z "$HSCT_HELENOS_ROOT" ]; then
	hsct_error "root not set in $HSCT_CONFIG"
	leave_script_err
fi
HSCT_DIST="$HSCT_HELENOS_ROOT/uspace/dist"


case "$1" in
	help)
		hsct_usage "$0"
		leave_script_ok
		;;
	clean|build|package|install|uninstall)
		HSCT_HARBOUR_NAME="$2"
		if [ -z "$HSCT_HARBOUR_NAME" ]; then
			hsct_usage "$0"
			leave_script_err
		fi
		;;
	env)
		HSCT_SHOW_EXPORTS=true
		hsct_prepare_env_build || leave_script_err
		hsct_prepare_env_package || leave_script_err
		leave_script_ok
		;;
	*)
		hsct_usage "$0"
		leave_script_err
		;;
esac


if ! [ -d "$HSCT_HOME/$HSCT_HARBOUR_NAME" ]; then
	hsct_error "Unknown package $1"
	leave_script_err
fi

if ! [ -r "$HSCT_HOME/$HSCT_HARBOUR_NAME/HARBOUR" ]; then
	hsct_error "HARBOUR file missing." >&2
	leave_script_err
fi

HSCT_DIST2="$HSCT_DIST/coast/$HSCT_HARBOUR_NAME/"

source "$HSCT_HOME/$HSCT_HARBOUR_NAME/HARBOUR"

case "$1" in
	clean)
		hsct_clean
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
	uninstall)
		hsct_uninstall
		;;
	*)
		hsct_error "Internal error, we shall not get to this point!"
		leave_script_err
		;;
esac

if [ $? -eq 0 ]; then
	leave_script_ok
else
	leave_script_err
fi
