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
HSCT_HSCT="$HSCT_HOME/hsct.sh"

HSCT_SOURCES_DIR=`pwd`/sources
HSCT_BUILD_DIR=`pwd`/build
HSCT_INCLUDE_DIR=`pwd`/include
HSCT_LIB_DIR=`pwd`/libs
HSCT_MISC_DIR=`pwd`/misc
HSCT_APPS_DIR=`pwd`/apps
HSCT_DISABLED_CFLAGS="-Werror -Werror-implicit-function-declaration"
HSCT_CACHE_DIR=`pwd`/helenos

hsct_usage() {
	echo "Usage:"
	echo " $1 action [package]"
	echo "    Action can be one of following:"
	echo "       clean     Clean built directory."
	echo "       build     Build given package."
	echo "       package   Save installable files to allow cleaning."
	echo "       install   Install to uspace/dist of HelenOS."
	echo "       uninstall Try to remove what was installed to uspace/dist."
	echo " $1 help"
	echo "    Display this help and exit."
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
hsct_error2() {
	echo "[hsct]:" "  ->  " "$@" >&2
}

hsct_run_echo() {
	echo "[hsct]:" "$@"
	"$@"
}

run() {
	hsct_run_echo "$@"
}

hsct_is_helenos_configured() {
	[ -e "$HSCT_HELENOS_ROOT/Makefile.config" ]
	return $?
}

hsct_print_condition_result() {
	if "$@"; then
		echo "true";
	else
		echo "false";
	fi
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

hsct_cache_variable() {
	export "$1=$2"
	(
		if [ -n "$3" ]; then
			echo "#" "$3"
		fi
		echo -n "export $1=\"";
		echo -n "$2" | sed -e 's#"#\\"#g' -e 's#\\#\\\\#g'
		echo "\""
	) >>"$HSCT_CACHE_DIR/env.sh"
}

hsct_init() {
	hsct_info "Caching headers, libraries and compile flags"
	
	mkdir -p "$HSCT_CACHE_DIR"
	(
		echo "#!/bin/sh"
		echo
		echo "# This is automatically generated file."
		echo "# All changes will be LOST upon next invocation of hsct.sh"
		echo
	) >"$HSCT_CACHE_DIR/env.sh"
	chmod +x "$HSCT_CACHE_DIR/env.sh"
	
	
	#
	# Start with binaries
	#

	hsct_cache_variable HSCT_CC `hsct_get_var_from_uspace CC`
	hsct_cache_variable HSCT_AS `hsct_get_var_from_uspace AS`
	hsct_cache_variable HSCT_LD `hsct_get_var_from_uspace LD`
	hsct_cache_variable HSCT_AR `hsct_get_var_from_uspace AR`
	hsct_cache_variable HSCT_STRIP `hsct_get_var_from_uspace STRIP`
	hsct_cache_variable HSCT_OBJCOPY `hsct_get_var_from_uspace OBJCOPY`
	hsct_cache_variable HSCT_OBJDUMP `hsct_get_var_from_uspace OBJDUMP`
	# HelenOS do not use ranlib or nm but some applications require it
	hsct_cache_variable HSCT_RANLIB `echo "$HSCT_AR" | sed 's/-ar$/-ranlib/'`
	hsct_cache_variable HSCT_NM `echo "$HSCT_AR" | sed 's/-ar$/-nm/'`
	
	#
	# Various paths
	#
	hsct_cache_variable HSTC_HELENOS_ROOT "$HSCT_HELENOS_ROOT"
	hsct_cache_variable HSCT_INCLUDE_DIR "$HSCT_INCLUDE_DIR"
	hsct_cache_variable HSCT_LIB_DIR "$HSCT_LIB_DIR"
	hsct_cache_variable HSCT_MISC_DIR "$HSCT_MISC_DIR"
	hsct_cache_variable HSCT_APPS_DIR "$HSCT_APPS_DIR"
	hsct_cache_variable HSCT_CACHE_DIR "$HSCT_CACHE_DIR"
	
	#
	# Get architecture, convert to target
	#
	hsct_cache_variable HSCT_UARCH `hsct_get_var_from_uspace UARCH`
	HSCT_TARGET=""
	case $HSCT_UARCH in
		ia32)
			HSCT_GNU_TARGET="i686-pc-linux-gnu"
			HSCT_HELENOS_TARGET="i686-pc-helenos"
			;;
		amd64)
			HSCT_GNU_TARGET="amd64-linux-gnu"
			HSCT_HELENOS_TARGET="amd64-helenos"
			;;
		mips32)
			HSCT_GNU_TARGET="mipsel-linux-gnu"
			HSCT_HELENOS_TARGET="mipsel-helenos"
			;;
		*)
			hsct_error 'Unsupported architecture: $(UARCH) =' "'$HSCT_UARCH'."
			return 1
			;;
	esac
	hsct_cache_variable HSCT_GNU_TARGET="$HSCT_GNU_TARGET"
	hsct_cache_variable HSCT_HELENOS_TARGET="$HSCT_HELENOS_TARGET"
	case `hsct_get_var_from_uspace COMPILER` in
		gcc_helenos)
			hsct_cache_variable HSCT_TARGET="$HSCT_HELENOS_TARGET"
			;;
		*)
			hsct_cache_variable HSCT_TARGET="$HSCT_GNU_TARGET"
			;;
	esac
	
	
	#
	# Copy the files and update the flags accordingly
	#
	mkdir -p "$HSCT_CACHE_DIR/include"
	mkdir -p "$HSCT_CACHE_DIR/lib"

	# Linker script
	hsct_info2 "Copying linker script and startup object file"
	_LINKER_SCRIPT=`hsct_get_var_from_uspace LINKER_SCRIPT`
	(
		set -o errexit
		_STARTUP_OBJECT=`sed -n 's#.*STARTUP(\([^)]*\)).*#\1#p' <"$_LINKER_SCRIPT" 2>/dev/null`
		cp "$_STARTUP_OBJECT" "$HSCT_CACHE_DIR/lib/entry.o" || return 1 
		sed "s#$_STARTUP_OBJECT#$HSCT_CACHE_DIR/lib/entry.o#" \
			<"$_LINKER_SCRIPT" >"$HSCT_CACHE_DIR/link.ld"
	)
	if [ $? -ne 0 ]; then
		hsct_error "Failed preparing linker script."
		return 1
	fi
	
	_LINKER_SCRIPT="$HSCT_CACHE_DIR/link.ld"
	
	# Libraries
	hsct_info2 "Copying libraries"
	cp \
		"$HSTC_HELENOS_ROOT/uspace/lib/c/libc.a" \
		"$HSTC_HELENOS_ROOT/uspace/lib/softint/libsoftint.a" \
		"$HSTC_HELENOS_ROOT/uspace/lib/softfloat/libsoftfloat.a" \
		"$HSTC_HELENOS_ROOT/uspace/lib/posix/libc4posix.a" \
		"$HSTC_HELENOS_ROOT/uspace/lib/posix/libposixaslibc.a" \
		"$HSCT_CACHE_DIR/lib/"
	if [ $? -ne 0 ]; then
		hsct_error "Failed copying libraries to cache."
		return 1
	fi
	
	# Headers
	hsct_info2 "Copying headers"
	(
		set -o errexit
		cp "$HSTC_HELENOS_ROOT/config.h" "$HSCT_CACHE_DIR/include/system_config.h"
		cp -L -R "$HSTC_HELENOS_ROOT/uspace/lib/posix/include/posix/" "$HSCT_CACHE_DIR/include/"
		mkdir -p "$HSCT_CACHE_DIR/include/libc"
		cp -L -R "$HSTC_HELENOS_ROOT/uspace/lib/c/include/"* "$HSCT_CACHE_DIR/include/libc"
		cp -L -R "$HSTC_HELENOS_ROOT/abi/include/abi/" "$HSCT_CACHE_DIR/include/"
		cp -L -R "$HSTC_HELENOS_ROOT/uspace/lib/c/arch/$HSCT_UARCH/include/libarch/" "$HSCT_CACHE_DIR/include/"
	)
	if [ $? -ne 0 ]; then
		hsct_error "Failed copying headers to cache."
		return 1
	fi
		
	
	
	#
	# Fix the flags
	#
	hsct_info2 "Fixing compiler flags"
	
	# Get the flags
	_CFLAGS=`hsct_get_var_from_uspace CFLAGS`
	_LDFLAGS=`hsct_get_var_from_uspace LFLAGS`
	
	# CC flags clean-up
	#_CFLAGS=`echo "$_CFLAGS" | sed 's#-imacros[ \t]*\([^ \t]*/config.h\)#-imacros '"$HSCT_CACHE_DIR"'/include/system_config.h#'`
	_CFLAGS_OLD="$_CFLAGS"
	_CFLAGS=""
	_next_kind="none"
	for _flag in $_CFLAGS_OLD; do
		_disabled=false
		case "$_next_kind" in
			skip)
				_disable=true
				;;
			imacro)
				if echo "$_flag" | grep -q '/config.h$'; then
					_flag="$HSCT_CACHE_DIR/include/system_config.h"
				fi
				;;
			*)
				;;
		esac
		_next_kind="none"
		
		for _disabled_flag in $HSCT_DISABLED_CFLAGS; do
			if [ "$_disabled_flag" = "$_flag" ]; then
				_disabled=true
				break
			fi
		done
		
		if [ "$_flag" = "-L" ]; then
			_next_kind="skip"
			_disabled=true
		fi
		if [ "$_flag" = "-I" ]; then
			_next_kind="skip"
			_disabled=true
		fi
		if [ "$_flag" = "-imacros" ]; then
			_next_kind="imacro"
		fi
		if echo "$_flag" | grep -q '^-[IL]'; then
			_disabled=true
		fi
		
		if ! $_disabled; then
			_CFLAGS="$_CFLAGS $_flag"
		fi
	done
	
	# LD flags clean-up
	_LDFLAGS_OLD="$_LDFLAGS"
	_LDFLAGS=""
	for _flag in $_LDFLAGS_OLD; do
		_disabled=false
		# Get rid of library paths, the files are stored locally
		if echo "$_flag" | grep -q '^-[L]'; then
			_disabled=true
		fi
		if ! $_disabled; then
			_LDFLAGS="$_LDFLAGS $_flag"
		fi
	done
	
	# Add paths to cached headers and libraries
	_LDFLAGS="$_LDFLAGS -L$HSCT_CACHE_DIR/lib -n -T $_LINKER_SCRIPT"
	_CFLAGS="$_CFLAGS -I$HSCT_CACHE_DIR/include/posix -I$HSCT_CACHE_DIR/include/"
	
	# Actually used libraries
	# The --whole-archive is used to allow correct linking of static libraries
	# (otherwise, the ordering is crucial and we usally cannot change that in the
	# application Makefiles).
	_POSIX_LINK_LFLAGS="--whole-archive --start-group -lposixaslibc -lsoftint --end-group --no-whole-archive -lc4posix"
	
	_LDFLAGS="$_LDFLAGS $_POSIX_LINK_LFLAGS"
	
	# The LDFLAGS might be used through CC, thus prefixing with -Wl is required
	_LDFLAGS_FOR_CC=""
	for _flag in $_LDFLAGS; do
		_LDFLAGS_FOR_CC="$_LDFLAGS_FOR_CC -Wl,$_flag"
	done
	
	hsct_cache_variable HSCT_LDFLAGS "$_LDFLAGS"
	hsct_cache_variable HSCT_LDFLAGS_FOR_CC "$_LDFLAGS_FOR_CC"
	hsct_cache_variable HSCT_CFLAGS "$_CFLAGS"
}

hsct_prepare_env() {
	if ! [ -e "$HSCT_CACHE_DIR/env.sh" ]; then
		hsct_error "Cache is not initialized. Maybe HelenOS is not configured?"
		return 1
	fi
	
	source "$HSCT_CACHE_DIR/env.sh"
}

hsct_clean() {
	hsct_info "Cleaning build directory..."
	rm -rf "$HSCT_BUILD_DIR/$shipname/"*
}

hsct_can_update_cache() {
	# If HelenOS is configured, we want to update the cache.
	# However, if architecture is specified only if the current
	# configuration is the same.
	_arch=`hsct_get_config "$HSCT_CONFIG" arch`
	if [ -z "$_arch" ]; then
		# Building for any architecture. We update the cache if
		# HelenOS is configured.
		hsct_is_helenos_configured
		return $?
	else
		# Update the cache only if HelenOS is configured and the
		# architecture matches
		if hsct_is_helenos_configured; then
			_uarch=`hsct_get_var_from_uspace UARCH`
			[ "$_uarch" = "$_arch" ]
			return $?
		else
			return 1
		fi
	fi
}

hsct_build() {
	mkdir -p "$HSCT_BUILD_DIR/$shipname"
	if [ -e "$HSCT_BUILD_DIR/${shipname}.built" ]; then
		hsct_info "No need to build $shipname."
		return 0
	fi
	
	if hsct_can_update_cache; then
		if ! hsct_init; then
			return 1
		fi
	fi
	
	# Check for prerequisities
	for tug in $shiptugs; do
		if ! [ -e "$HSCT_BUILD_DIR/${tug}.packaged" ]; then
			hsct_info "Need to build $tug first."
			hsct_info2 "Running $HSCT_HSCT package $tug"
			(
				$HSCT_HSCT package $tug
				exit $?
			) || return 1
			hsct_info2 "Back from building $tug."
		fi
	done
	
	hsct_prepare_env || return 1
	
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
	mkdir -p "$HSCT_INCLUDE_DIR" || { hsct_error "Failed to create include directory."; return 1; }
	mkdir -p "$HSCT_LIB_DIR" || { hsct_error "Failed to create library directory."; return 1; }
	mkdir -p "$HSCT_MISC_DIR" || { hsct_error "Failed to create miscellaneous directory."; return 1; }
	mkdir -p "$HSCT_APPS_DIR" || { hsct_error "Failed to create apps directory."; return 1; }
	
	if [ -e "$HSCT_BUILD_DIR/${shipname}.packaged" ]; then
		hsct_info "No need to package $shipname."
		return 0;
	fi
	
	hsct_build || return 1
	
	hsct_prepare_env || return 1
	
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

	if ! hsct_can_update_cache; then
		hsct_error "Installation cannot be performed."
		hsct_error2 "HelenOS is not configured for the proper architecture."
		return 1
	fi

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
	hsct_prepare_env || return 1

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

hsct_global_init() {
	if [ -e "$HSCT_CONFIG" ]; then
		hsct_error "Directory is already initialized ($HSCT_CONFIG exists)."
		return 1
	fi
	
	hsct_info "Initializing this build directory."
	_root_dir=`( cd "$1"; pwd ) 2>/dev/null`
	if ! [ -e "$_root_dir/HelenOS.config" ]; then
		hsct_error "$1 does not look like a valid HelenOS directory.";
		return 1
	fi
	
	# If no architecture is specified, we would read it from
	# Makefile.config
	_uarch=`hsct_get_var_from_uspace UARCH`
	if [ -z "$2" ]; then	
		if [ -z "$_uarch" ]; then
			hsct_error "HelenOS is not configured and you haven't specified the architecture";
			return 1
		fi
	fi
	if [ "$3" = "build" ]; then
		if [ "$_uarch" != "$2" ]; then
			(
				set -o errexit
				cd "$_root_dir"
				hsct_info2 "Cleaning previous configuration in $PWD."
				make distclean >/dev/null 2>&1
				hsct_info2 "Configuring for $2."
				make Makefile.config "PROFILE=$2" HANDS_OFF=y >/dev/null
				hsct_info2 "Building (may take a while)."
				make >/dev/null 2>&1
			)
			if [ $? -ne 0 ]; then
				hsct_error "Failed to automatically configure HelenOS for $2."
				return 1
			fi
			_uarch=`echo "$2" | cut '-d/' -f 1`
		fi
	fi
	
	hsct_info2 "Generating the configuration file."
	cat >$HSCT_CONFIG <<EOF_CONFIG
root = $_root_dir
arch = $_uarch
EOF_CONFIG
}

alias leave_script_ok='return 0 2>/dev/null || exit 0'
alias leave_script_err='return 1 2>/dev/null || exit 1'

HSCT_CONFIG=hsct.conf


if [ "$1" = "init" ]; then
	HSCT_HELENOS_ROOT="$2"
else
	if ! [ -e "$HSCT_CONFIG" ]; then
		hsct_error "Configuration file $HSCT_CONFIG missing."
		leave_script_err
	fi
	HSCT_HELENOS_ROOT=`hsct_get_config "$HSCT_CONFIG" root`
	HSCT_HELENOS_ARCH=`hsct_get_config "$HSCT_CONFIG" arch`
	
	if [ -z "$HSCT_HELENOS_ARCH" ]; then
		hsct_error "I don't know for which architecture you want to build."
		leave_script_err
	fi
fi

if [ -z "$HSCT_HELENOS_ROOT" ]; then
	hsct_error "I don't know where is the HelenOS source root."
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
	init)
		hsct_global_init "$2" "$3" "$4"
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
