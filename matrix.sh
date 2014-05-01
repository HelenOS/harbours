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

HELENOS_ROOT="$1"
ARCHITECTURES="$2"
HARBOURS="$3"
PARALLELISM=8

HSCT_HOME=`which -- "$0" 2>/dev/null`
# Maybe, we are running Bash
[ -z "$HSCT_HOME" ] && HSCT_HOME=`which -- "$BASH_SOURCE" 2>/dev/null`
HSCT_HOME=`dirname -- "$HSCT_HOME"`
HSCT="$HSCT_HOME/hsct.sh"

msg() {
	echo ">>>" "$@" >&2
}
msg2() {
	echo "    =>" "$@" >&2
}
msg3() {
	echo "       ->" "$@" >&2
}

log_tail() {
	tail -n 5 "$1" | sed 's#.*#       !!! &#'
}

arch_human_readable() {
	_arch=`echo "$1" | cut '-d-' -f 1`
	_machine=`echo "$1" | cut '-d-' -f 2-`
	[ "$_machine" = "$_arch" ] && _machine="";
	echo "<span class=\"arch\">"
	case "$_arch" in
		ia32) echo "IA 32";;
		ia64) echo "IA 64";;
		amd64) echo "AMD 64";;
		arm32) echo "ARM 32";;
		mips32) echo "MIPS 32";;
		mips64) echo "MIPS 64";;
		ppc32) echo "PowerPC 32";;
		sparc32) echo "SPARC 32";;
		sparc64) echo "SPARC 64";;
		*) echo "$_arch";;
	esac
	echo "</span>"
	if [ -z "$_machine" ]; then
		echo ""
	else
		echo "<br /><span class=\"machine\">"
	fi
	case "$_machine" in
		beagleboardxm) echo "BeagleBoard-xM";;
		beaglebone) echo "BeagleBone";;
		gta02) echo "GTA02";;
		integratorcp) echo "Integrator/CP";;
		raspberrypi) echo "Raspberry Pi";;
		malta-be) echo "Malta (BE)";;
		malta-le) echo "Malta (LE)";;
		msim) echo "MSIM";;
		i460gx) echo "i460GX";;
		leon3) echo "LEON3";;
		"") ;;
		*) echo "$_machine";;
	esac
	[ -z "$_machine" ] || echo "</span>"
}

#
# Resolve correct ordering of all harbours
#

# Allow hide harbours temporarily by prefixing them with e.g. _underscore
ALL_HARBOURS=`ls $HSCT_HOME/[a-zA-Z]*/HARBOUR | sed 's#.*/\([^/]*\)/HARBOUR$#\1#'`

# Export dependencies to HARBOUR_DEPS_{harbour_name}
for harbour in $ALL_HARBOURS; do
	deps=`cd $HSCT_HOME/$harbour/; . ./HARBOUR ; echo $shiptugs`
	eval HARBOUR_DEPS_$harbour="\"$deps\""
done


# Determine the correct ordering
ALL_HARBOURS_CORRECT_ORDER=""
HARBOURS_NOT_RESOLVED="$ALL_HARBOURS"

while [ -n "$HARBOURS_NOT_RESOLVED" ]; do
	not_resolved_yet=""
	sed_remove="-e s:x:x:"
	found_one=false
	for harbour in $HARBOURS_NOT_RESOLVED; do
		deps=`eval echo \\$HARBOUR_DEPS_$harbour`
		if [ -z "$deps" ]; then
			ALL_HARBOURS_CORRECT_ORDER="$ALL_HARBOURS_CORRECT_ORDER $harbour";
			sed_remove="$sed_remove -e s:$harbour::g"
			found_one=true
		else
			not_resolved_yet="$not_resolved_yet $harbour";
		fi
	done
	for harbour in $ALL_HARBOURS; do
		deps=`eval echo \\$HARBOUR_DEPS_$harbour | sed $sed_remove`
		eval HARBOUR_DEPS_$harbour="\"$deps\""
	done
	HARBOURS_NOT_RESOLVED="$not_resolved_yet"
	if ! $found_one; then
		echo "There is circular dependency!"
		exit 1
	fi
done

ALL_HARBOURS="$ALL_HARBOURS_CORRECT_ORDER"

# -- End of correct ordering resolving



if [ -z "$HELENOS_ROOT" ]; then
	RESULTS=true
	BUILD=false
else
	RESULTS=true
	BUILD=true
fi


if $BUILD; then
	[ -z "$ARCHITECTURES" ] && exit 1
	[ -z "$HARBOURS" ] && exit 1
	
	if [ "$ARCHITECTURES" == "all" ]; then
		ARCHITECTURES="amd64 arm32/beagleboardxm arm32/beaglebone arm32/gta02 arm32/integratorcp arm32/raspberrypi ia32 ia64/i460GX ia64/ski mips32/malta-be mips32/malta-le mips32/msim mips64/msim ppc32 sparc32/leon3 sparc64/niagara sparc64/ultra"
	fi
	if [ "$HARBOURS" == "all" ]; then
		HARBOURS="$ALL_HARBOURS"
	fi
fi

msg "Harbour status matrix generator."
if $BUILD; then
	msg2 "HelenOS root is at $HELENOS_ROOT."
fi
msg2 "Coastline builder is at $HSCT."

if $BUILD; then
	msg "Matrix generation started."
	msg2 "Removing old results..."

	rm -rf matrix
	mkdir -p matrix
	mkdir -p mirror
		
	for ARCH in $ARCHITECTURES; do
		ARCH_FILENAME="`echo $ARCH | tr '/' '-'`"
		ARCH_DIR="build-$ARCH_FILENAME"
		TARBALL_DIR="matrix/$ARCH_FILENAME"
		msg ""
		msg "Building for $ARCH (into $ARCH_DIR)."
		msg ""
		mkdir -p "$ARCH_DIR"
		mkdir -p "$TARBALL_DIR"
		(
			cd $ARCH_DIR
			
			if ! [ -r hsct.conf ]; then
				(
					set -o errexit
					msg2 "Preparing for first build..."
					$HSCT init "$HELENOS_ROOT" "$ARCH" build &>init.log
					echo "parallel = $PARALLELISM" >>hsct.conf
					echo "sources = ../mirror/" >>hsct.conf
				)
				if [ $? -ne 0 ]; then
					log_tail init.log
					exit 1
				fi
			fi
			
			for HARBOUR in $HARBOURS; do
				(
					set -o errexit
					mkdir -p build
					echo -n "" >build/$HARBOUR.log
					
					msg2 "Building $HARBOUR..."
					$HSCT build $HARBOUR >build/$HARBOUR.log 2>&1
					
					msg3 "Packaging..."
					$HSCT package $HARBOUR >>build/$HARBOUR.log 2>&1
					
					msg3 "Creating the tarball..."
					$HSCT archive $HARBOUR >>build/$HARBOUR.log 2>&1
					
					cp archives/$HARBOUR.tar.xz ../$TARBALL_DIR/$ARCH_FILENAME-$HARBOUR.tar.xz
				)
				if [ $? -ne 0 ]; then
					log_tail build/$HARBOUR.log
				fi
				msg3 "Cleaning the build directory..."
				rm -rf build/$HARBOUR/
				cp build/$HARBOUR.log ../$TARBALL_DIR/$HARBOUR.txt
			done
		)
	done
fi

if $RESULTS; then
	msg "Generating HTML results page."
	ARCHS=`find matrix/* -type d | cut '-d/' -f 2-`
	BUILD_HARBOURS=`find matrix/* -name '*.txt' | cut '-d/' -f 3 | cut '-d.' -f 1 | sort | uniq | paste '-sd '`
	BUILD_HARBOURS_COUNT=`echo $BUILD_HARBOURS | wc -w`
	COL_WIDTH=$(( 100 / ( $BUILD_HARBOURS_COUNT + 1 ) ))
	FIRST_COL_WIDTH=$(( 100 - $BUILD_HARBOURS_COUNT * $COL_WIDTH ))
	
	BUILD_HARBOURS_ORDERED=""
	for HARBOUR in $ALL_HARBOURS; do
		if ! echo " $BUILD_HARBOURS " | grep " $HARBOUR " -q; then
			continue
		fi
		BUILD_HARBOURS_ORDERED="$BUILD_HARBOURS_ORDERED $HARBOUR"
	done
	BUILD_HARBOURS="$BUILD_HARBOURS_ORDERED"
	(
		cat <<EOF_HTML_HEADER
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>HelenOS coastline status matrix</title>
<style type="text/css">
BODY {
	font-family: Verdana,Arial,sans-serif;
}
H1 {
	text-align: center;
	font-size: 200%;
	color: #036;
}
A:link, A:visited {
	color: #036;
}
A:hover {
	background: #036;
	color: white;
}
TABLE.coastline {
	margin: auto;
	width: 100%;
}
TABLE.coastline, TABLE.coastline TH, TABLE.coastline TD {
	font-weight: normal;
	border: 1px solid black;
	border-collapse: collapse;
	padding: 4px 2px;
	background: #FFFAF0;
	text-align: center;
	line-height: 130%;
	vertical-align: middle;
}
TABLE.coastline TH.package .version {
	font-size: 80%;
}
TABLE.coastline TD.ok {
	background: #cfc;
}
TABLE.coastline TD.fail {
	background: #fcc;
}
TD.ok .msg {
	color: #030;
}
TD.fail .msg {
	color: #300;
}
TABLE.coastline A {
	padding: 2px;
}
TABLE.coastline A:link, TABLE.coastline A:visited {
	color: #036;
}
TABLE.coastline A:hover {
	background: #036;
	color: white;
}
</style>
</head>
<body>
<h1>HelenOS coastline status matrix</h1>
<p>
This matrix summarizes status of porting various packages to 
<a href="http://www.helenos.org">HelenOS</a>
through
<a href="https://github.com/vhotspur/coastline">Coastline</a>.
The results here come from completely
<a href="http://vh.alisma.cz/blog/2013/03/30/introducing-helenos-coastline/">automated
process</a>
and it is possible that some failed packages <i>can</i> be installed through some
manual tweaks.
</p>

<table class="coastline">
	<colgroup>
		<col width="$FIRST_COL_WIDTH%" />
		<col span="$ARCH_COUNT" width="$COL_WIDTH%" />
	</colgroup>
	<tr>
		<th>&nbsp;</th>
EOF_HTML_HEADER
		for HARBOUR in $BUILD_HARBOURS; do
			echo "<th class=\"package\">"
			echo "$HARBOUR <br />"
			VERSION=`sed -n 's#^[ \t]*shipversion=\(.*\)$#\1#p' <$HSCT_HOME/$HARBOUR/HARBOUR 2>/dev/null | tr -d "'\""`
			echo "<span class=\"version\">$VERSION</span>"
			echo "</th>"
		done
		echo "</tr>"
		
		for ARCH in $ARCHS; do
			echo "<tr>"
			
			echo "<th>"
			arch_human_readable "$ARCH"
			echo "</th>"
			for HARBOUR in $BUILD_HARBOURS; do
				if [ -e matrix/$ARCH/$ARCH-$HARBOUR.tar.xz ]; then
					TD_CLASS="ok"
					TD_MSG="OK"
					TD_LINK="$ARCH/$ARCH-$HARBOUR.tar.xz"
					TD_LINK_TEXT="Tarball"
				else
					TD_CLASS="fail"
					TD_MSG="FAILED"
					TD_LINK="$ARCH/$HARBOUR.txt"
					TD_LINK_TEXT="Log"
				fi
				echo "<td class=\"$TD_CLASS\">"
				echo "<span class=\"msg\">$TD_MSG</span><br />"
				echo "<a href=\"$TD_LINK\">$TD_LINK_TEXT</a>"
				echo "</td>"
			done
			
			echo "</tr><!-- $ARCH -->"
		done
		cat <<EOF_HTML_FOOTER
</table>
</body>
</html>
EOF_HTML_FOOTER
	) >matrix/index.html
fi
