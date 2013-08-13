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

The script currently supports only static libraries (to be more precise, I
never tried to build any shared library with it) and thus you need to build
HelenOS first.
Some of the prepared packages depends on some changes in ``libposix`` that
are not yet in mainline, thus it is recommended to build against
`lp:~vojtech-horky/helenos/gcc-port <https://code.launchpad.net/~vojtech-horky/helenos/gcc-port>`_.

``~/helenos/gcc-port`` might be a good location where to make the
checkout.
Once you checkout the branch, configure it for ``ia32`` and build it.
Running::

	make PROFILE=ia32 HANDS_OFF=y
	
shall do it.

After the build is complete, it is possible to actually compile and build
some of the ported software.
But before that, a ``hsct.conf`` has to be prepared in
``~/helenos/coast-builds/ia32`` that contains the following line (path
to the actual HelenOS root)::

	root = /home/username/helenos/gcc-port

Then, change directory to ``~/helenos/coast-builds/ia32`` and execute the
following command to build `zlib <http://www.zlib.net/>`_::

	~/helenos/coast/hsct.sh build zlib
	
If all is well, zlib sources shall be fetched, zlib shall be configured
and built.
Inside directory ``build/zlib/zlib-1.2.7`` shall reside the compiled library.

Issuing::

	~/helenos/coast/hsct.sh package zlib
	
would copy the compiled library and some example applications outside of
the build tree to allow removing the build directory if you are low on free
disk space.

Finally, running::

	~/helenos/coast/hsct.sh install zlib

would copy zlib to HelenOS source tree so that you can actually try it live.
After booting HelenOS, ``minigzip`` shall be available in ``/coast/zlib``.

If you often compile for different architectures, you may want to use the
``arch`` option in ``hsct.conf`` (it is recommended to use it anyway).
It contains the short architecture name (such as ``ia32`` or ``mips32``)::

	arch = ia32

and it is checked against currently selected architecture inside your HelenOS
source tree prior building.
This ensures that you do not mix different architecture accidentally.
Empty or missing value means that no check is done at all.




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
To simplify this it is possible to run the ``hsct.sh`` script in mode when
it only prints (and exports) all the ``$HSCT_`` variables.

Running::

	~/helenos/coast/hsct.sh env

would list the variables available.
If this command is sourced (notice the dot at the beginning)::

	. ~/helenos/coast/hsct.sh env
	
then the printed variables are actually created in the current shell.
You can then use them when running the commands responsible for the
application building.

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

Following variables are useful when the application is successfully built
and you want to copy some of the created files elsewhere.
E.g. to the HelenOS source tree so they could become part of the generated
image.

- ``$HSCT_INCLUDE_DIR``: Points to directory for header files.
- ``$HSCT_LIB_DIR``: Points to directory for libraries.
- ``$HSCT_MISC_DIR``: Points to directory for any other stuff.
  It is recommended to create a subdirectory ``$HSCT_MISC_DIR/application-name``
  for these extra files).

For example, the ``./configure`` script for `libgmp <http://gmplib.org/>`_
uses the following variables::

	./configure \
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

Look into existing files how does this process typically looks like.

If you want to print an informative message to the screen, it is recommended
to use ``msg()`` function as it would make the message more visible.

To simplify debugging it is recommended to run commands prefixed with
function named ``run``.
That way the actual command is first printed to the screen and then
executed.

Once the application is built it is necessary to copy its files to a more
permanent storage (to allow clean-up of the build directory) and finally copy
the files to the HelenOS source tree.

The function ``package()`` copies the files outside of the build directory
and it typically consists of similar commands
(this one is taken from ``zlib``)::

	package() {
		# shipname is "zlib" here
		cd "${shipname}-${shipversion}"
		
		# Pretend we are actually installing
		run make install "DESTDIR=$PWD/PKG"
		
		# Copy the headers and static library
		run cp PKG/usr/local/include/zlib.h PKG/usr/local/include/zconf.h "$HSCT_INCLUDE_DIR/"
		run cp PKG/usr/local/lib/libz.a "$HSCT_LIB_DIR/"
	}
	
The ``dist()`` function is used to copy these files to the HelenOS source
tree.
You have following two variables to simplify the path specification:

- ``$HSCT_DIST``: points to ``uspace/dist`` inside the source tree.
- ``$HSCT_DIST2``: points to ``uspace/dist/coast/$shipname``.
  However, you first need to create this directory.

Typically, the ``dist()`` function looks like this::

	dist() {
		run mkdir -p "$HSCT_DIST2"
		run cp "$HSCT_MISC_DIR/${shipname}/"* "$HSCT_DIST2"
	}

Finally, there is ``undist()`` function that removes the files from the
HelenOS source tree.
Typical implementation is very simple::

	undist() {
		run rm -rf "$HSCT_DIST2"
	}

