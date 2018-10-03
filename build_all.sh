#!/bin/sh

helenos_dir=$1

profiles="amd64 ia64/ski ia32 arm32/integratorcp mips32/msim ppc32 riscv64 sparc64/ultra"

profiles="$profiles arm32/beagleboardxm arm32/beaglebone arm32/gta02 arm32/raspberrypi"
profiles="$profiles ia64/i460GX mips32/malta-be mips32/malta-le sparc64/niagara"

# Order matters, dependencies must come before dependents.
harbours="binutils fdlibm libgmp libisl libmpfr libmpc zlib gcc jainja libiconv libpng lua msim pcc python2"

excludes=`cat<<EOF
ia64/i460GX:pcc
ia64/ski:pcc
arm32/beagleboardxm:pcc
arm32/beaglebone:pcc
arm32/gta02:pcc
arm32/integratorcp:pcc
arm32/raspberrypi:pcc
riscv64:pcc
riscv64:binutils
riscv64:gcc
sparc64/niagara:pcc
sparc64/ultra:pcc
EOF`


if [ -z "$helenos_dir" ]; then
	echo "You need to specify helenos directory on the command line."
	exit 1
fi

helenos_dir=`realpath $helenos_dir`
echo "HelenOS directory: $helenos_dir"

if [ -x build ]; then
	echo "build directory already exists"
	exit 1
fi

mkdir build
cd build

for p in $profiles; do
	pdir=`echo $p | sed 's/\//_/g'`

	mkdir $pdir
	cd $pdir

	printf "%-32s  " "$p"

	../../hsct.sh init $helenos_dir $p >helenos.log 2>&1

	if [ $? -eq 0 ]; then
		echo "OK"
		cd ..
	else
		echo "FAILED"
		cd ..
		rm -rf $pdir
	fi
done

for p in $profiles; do
	pdir=`echo $p | sed 's/\//_/g'`

	cd $pdir || continue

	for h in $harbours; do
		printf "%-32s  " "$p:$h"

		echo "$excludes" | grep "$p:$h" > /dev/null
		if [ $? -eq 0 ]; then
			echo "ign"
			continue
		fi

		../../hsct.sh archive --no-deps $h >$h.log 2>&1
		rc=$?
		case $rc in
		"0")
			echo "OK"
			;;
		"62" | "63")
			echo "FAILED FETCH"
			;;
		"64")
			echo "dep"
			;;
		"66")
			echo "FAILED BUILD"
			;;
		*)
			echo "FAILED $rc"
			;;
		esac
	done

	cd ..
done
