HelenOS coastline: build POSIX applications for HelenOS
=======================================================

This repository contains scripts that should simplify porting POSIX
applications to run in HelenOS.
The motivation for this mini-project is that porting GNU/POSIX applications
to HelenOS is mostly about setting correctly the CFLAGS when running
``./configure`` and then copying the generated executables somewhere to
``uspace/dist``.
The idea is that this procedure would be recorded in a form of a simple shell
script, called HARBOUR (because it is a port).
The wrapper script ``hsct.sh`` then takes care of downloading the necessary
sources and running the user-defined commands.


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
to the actual HelenOS root):

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

	~/helenos/coast/hsct.sh package zlib

would copy zlib to HelenOS source tree so that you can actually try it live.
After booting HelenOS, ``minigzip`` shall be available in ``/coast/zlib``.


Writing your own HARBOUR files
------------------------------
This part would be finished later.
For now, following hints must be sufficient:

- take inspiration from existing harbours
- variable ``shipsources`` must contain the required sources,
  separate them by spaces
  
  - local files (e.g. patches) are referenced just by the file name
  - wget is used for downloading them

- function ``build`` is invoked when building the package
  
  - it must take care of unpacking the source
  - configuring it
  - and finally building it
  - following variables are available (not all of the are listed here,
    run ``~/helenos/coast/hsct.sh env`` for a full list)
    
    - ``$HSCT_CC`` - C compiler to use
    - ``$HSCT_CFLAGS`` - C flags to use
    - ``$HSCT_LDFLAGS`` - linker flags
    - ``$HSCT_LDFLAGS_FOR_CC`` - linker flags preceded by ``-Wl,`` - useful
      when ``CC`` is used for linking as well
      

- function ``package`` shall copy headers, libraries and executables outside
  of the source tree

  - ``$HSCT_INCLUDE_DIR`` points to directory for header files
  - ``$HSCT_LIB_DIR`` points to directory for libraries
  - ``$HSCT_MISC_DIR`` points to directory for other stuff (it is recommended
    to create a subdirectory ``$HSCT_MISC_DIR/$shipname`` for these extra
    files)

- function ``dist`` copies files to HelenOS source tree

  - ``$HSCT_DIST`` points to ``uspace/dist`` inside the source tree
  - ``$HSCT_DIST2`` points to ``uspace/dist/coast/$shipname`` (but you need
    to create this directory first)

- function ``undist`` removes files copied by ``dist``
- it is highly recommended to precede all the commands with ``run`` to
  echo them to the screen
- for custom messages, you may call ``msg``
