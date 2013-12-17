HelenOS coastline: build POSIX applications for HelenOS
=======================================================

This repository contains scripts that should simplify porting POSIX
applications to run in `HelenOS <http://www.helenos.org>`_.
The motivation for this mini-project is that porting GNU/POSIX applications
to HelenOS is mostly about setting correctly the CFLAGS when running
``./configure`` and then copying the generated executables somewhere to
``uspace/dist``.
The idea is that this procedure would be recorded in a form of a simple shell
script, called harbour (because it is a port).
The wrapper script ``hsct.sh`` then takes care of downloading the necessary
sources and running the user-defined commands from respective ``HARBOUR`` file.

The whole idea is highly inspired by
`makepkg <https://wiki.archlinux.org/index.php/Makepkg>`_.


**WARNING**: some information here is obsoleted.
I will try to update it as soon as possible.

Using the coastline
-------------------
First, clone this repository somewhere on your disk.
The examples below would assume ``~/helenos/coast``.

Next, prepare the directory where the actual building of the POSIX
applications would happen.
It is recommended to do this outside HelenOS source tree and outside of the
coast-line sources.
``~/helenos/coast-builds/ia32`` is a good choice if you plan to build for
``ia32`` configuration.

Next, you obviously need check-out of HelenOS sources.
In the following examples, I would assume ``~/helenos/mainline``.

To use the coastline, go into the ``~/helenos/coast-builds/ia32`` and
issue the following command::

	~/helenos/coast/hsct.sh init ~/helenos/mainline ia32 build

This command would initialize the build directory and forcefully rebuild
HelenOS to the defaults of ``ia32`` configuration.
Once this command finishes, you can freely play inside ``~/helenos/mainline``
as all the necessary files are already cached in the build directory.

Now you can build some software.
Just choose one (for example, ``msim``) and run::

	~/helenos/coast/hsct.sh build msim

It may take a while but it shall eventually produce the simulator binary.
If you want to copy it to your HelenOS source tree, run::

	~/helenos/coast/hsct.sh install msim
	
If you want to transfer the built files to another machine etc, you may
want to run::

	~/helenos/coast/hsct.sh archive msim
	
that produces a TAR.XZ file in ``archives`` that you can directly unpack
into the ``uspace/overlay`` directory.

If you have a multicore machine, you may try setting the variable
``parallel`` in ``hsct.conf`` inside your build directory to a higher
value to allow parallel builds.




Writing your own HARBOUR files
------------------------------
The ``HARBOUR`` file is actually a shell script fragment.
The coastline script ``hsct.sh`` expects to find some variables and functions
declared in it.
These variables declare URLs of the source tarballs or versions while the
functions actually build (or install) the application/library/whatever.

Each ``HARBOUR`` is supposed to be in a separate directory.
This directory is placed together with the ``hsct.sh`` script.

The commands in individual functions are expected to use special
variables prepared by the wrapper script that would contain information
about selected compiler (i.e. full path to GCC) or flags for the compiler
to use.
These variables are prefixed with ``HSCT_`` followed by the name commonly
used in ``Makefile``\s or in ``configure`` scripts
(e.g. ``HSCT_CC`` contains path to the C compiler).

However, usually it is not possible to write the ``HARBOUR`` file directly:
for example various arguments to ``./configure`` scripts have to be tried
or extra ``CFLAGS`` might be necessary.

For testing, you can use the ``helenos/env.sh`` script and source it.
This script sets all the variables that you can use in the HARBOUR script.

Follows a shortened list of variables available.

- ``$HSCT_CC``: C compiler to use.
- ``$HSCT_CFLAGS``: C flags to use.
- ``$HSCT_LD``: linker to use.
- ``$HSCT_LDFLAGS``: linker flags
- ``$HSCT_LDFLAGS_FOR_CC``: linker flags preceded by ``-Wl,``.
  This is extremely useful when linker is not called explicitly and compiler
  is used for linking as well.
  Some of the flags would be recognized during the compilation phase so
  marking them as linker-specific effectively hides them.
- ``$HSCT_GNU_TARGET``: Target for which the application is being built.
  Typically this is the value for the ``--target`` option of the ``configure``
  script.
- ``$HSCT_INCLUDE_DIR``: Points to directory for header files.
  This directory is shared by all packages.
- ``$HSCT_LIB_DIR``: Points to directory for libraries.
- ``$HSCT_MY_DIR``: Points to installation directory.
  All files that shall appear in HelenOS must be copied here.
  The structure of this directory shall mirror the HelenOS one
  (i.e. the ``app/`` and ``inc/`` directories).

For example, the ``./configure`` script for `libgmp <http://gmplib.org/>`_
uses the following variables::

	run ./configure \
		--disable-shared \
		--host="$HSCT_GNU_TARGET" \
		CC="$HSCT_CC" \
		CFLAGS="$HSCT_CFLAGS $HSCT_LDFLAGS_FOR_CC <more flags>" \
		LD="$HSCT_LD"

Once you know the command sequence that leads to a successful built you
should record this sequence into the ``HARBOUR`` file.
The easiest way is to take an existing one and just change it for the
particular application.

The variable ``shipname`` declares the package (application or library)
name and shall be the same as the directory the ``HARBOUR`` is part of.

The variable ``shipsources`` contains space separated list of tarballs
or other files that needs to be downloaded.
Obviously, you can use ``$shipname`` inside as shell does the expansion.
To simplify updating of the packages, it is a good practice to have
variable ``$shipversion`` containing the application version and use this
variable inside ``$shipsources``.
If you need to reference a local file (a patch for example),
just write a bare name there.
The files are downloaded with ``wget`` so make sure the protocol used
and the path format is supported by this tool.

The variable ``shiptugs`` declares packages this one depends on
(the twisted fun is here that tugs are required for the ship to actually
leave the harbour).
That is a string with space separated list of other ships.

For building is used a ``build()`` function.
The function is expected to complete the following tasks:

- unpack the tarballs
- configure the application or somehow prepare it for building
- actually build it

If you want to print an informative message to the screen, it is recommended
to use ``msg()`` function as it would make the message more visible.

To simplify debugging it is recommended to run commands prefixed with
function named ``run``.
That way the actual command is first printed to the screen and then
executed.

Below is an example from ``libgmp`` that illustrates a typical
``build()`` function::

	# Manually extract the files
	run tar xjf "${shipname_}-${shipversion}.tar.bz2"
	
	# HelenOS-specific patches are needed
	msg "Patching gmp.h..."
	patch -p0 <gmp-h.patch
	
	# Run the configure script, notice the extra C flags
	cd "${shipname_}-${shipversion}"
	run ./configure \
		--disable-shared \
		--host="$HSCT_GNU_TARGET" \
		CC="$HSCT_CC" \
		CFLAGS="$HSCT_CFLAGS $HSCT_LDFLAGS_FOR_CC -D_STDIO_H -DHAVE_STRCHR -Wl,--undefined=longjmp" \
		LD="$HSCT_LD" \
		|| return 1
	
	# The variable $shipfunnels reflects maximum parallelism allowed
	# by the HARBOUR and by the current build directory
	msg "Building the library..."
	run make -j$shipfunnels
	
	# Tests are built and run as one target so this target always fails
	# We check that the tests were built by explicitly checking for
	# them below.
	msg "Building the tests..."
	run make check || true
	(
		cd tests
		# Check that all tests were built
		find t-bswap t-constants t-count_zeros t-gmpmax t-hightomask \
			t-modlinv t-popc t-parity t-sub
		exit $?
	)

After the application is built, it can be either archived or copied to
HelenOS source tree.
Both these actions requires that the application is *packaged* first.

The function ``package()`` is expected to copy the necessary files outside
of the build directory into ``$HSCT_MY_DIR``.
If there are some headers or libraries used by other packages, they should
be copied into ``$HSCT_INCLUDE_DIR`` and ``$HSCT_LIB_DIR``.

Directories ``$HSCT_INCLUDE_DIR`` and ``$HSCT_LIB_DIR`` behave as standard
Unix-like ``/usr/include`` and ``/usr/lib`` directories, while ``$HSCT_MY_DIR``
mirros the HelenOS directory ``uspace/dist`` structure.
Contents of ``$HSCT_MY_DIR`` is copied to ``uspace/overlay`` during
installation or tarred when archived.

Below is an excerpt from ``zlib`` ``package()`` function.
Notice the usage of the variables and the ``run()`` function::

	cd "${shipname}-${shipversion}"
	run make install DESTDIR=$PWD/PKG
	
	# Copy the headers and static library
	run cp PKG/usr/local/include/zlib.h PKG/usr/local/include/zconf.h "$HSCT_INCLUDE_DIR/"
	run cp PKG/usr/local/lib/libz.a "$HSCT_LIB_DIR/"
	
	run mkdir -p "$HSCT_MY_DIR/inc/c"
	run cp PKG/usr/local/include/zlib.h PKG/usr/local/include/zconf.h "$HSCT_MY_DIR/inc/c"
	
	run mkdir -p "$HSCT_MY_DIR/lib"
	run cp PKG/usr/local/lib/libz.a "$HSCT_MY_DIR/lib"
