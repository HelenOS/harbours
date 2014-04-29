#
# Copyright (c) 2014 Martin Decky
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

BINARY = jainja

JAINJA_SRC = src
FDLIBM_SRC = fdlibm53

LDFLAGS = \
	-L$(HSCT_CACHE_LIB) \
	$(HSCT_LDFLAGS)

CFLAGS = \
	$(HSCT_CFLAGS) \
	-I$(HSCT_CACHE_INCLUDE)/libc/ \
	-Wno-error \
	-I$(JAINJA_SRC)/include \
	-I$(JAINJA_SRC)/native \
	-I$(JAINJA_SRC)/tinygc \
	-D_IEEEFP_H \
	-DJCGO_UNIX \
	-DJCGO_UNIFSYS \
	-DJCGO_NOSYSNAME \
	-DEXTRASTATIC=static \
	-DJNUBIGEXPORT=static \
	-DJNIIMPORT=static \
	-DJNIEXPORT=static \
	-DJCGO_STDCLINIT \
	-DFPINIT= \
	-DGC_GETENV_SKIP \
	-DGC_CLIBDECL= \
	-DALL_INTERIOR_POINTERS \
	-DGC_GCJ_SUPPORT \
	-DCFASTCALL= \
	-DJCGO_UTFWCTOMB \
	-DJCGO_CLOCKGETTM \
	-DJCGO_NOUTIMBUF \
	-D_SYS_IOCTL_H \
	-D_SYS_SELECT_H \
	-D_IO_H \
	-DJCGO_BIGFLKOFF_T \
	-D_MATH_NO_HYPOT \
	-DGC_LP_ALLOCATOR \
	-DGC_INITIAL_HEAP_SIZE=64*1024*1024 \
	-DGC_MAXIMUM_HEAP_SIZE=128*1024*1024 \
	-DGC_FASTCALL= \
	-DGC_CLIBDECL= \
	-DGC_GCJ_SUPPORT

SOURCES = \
	$(FDLIBM_SRC)/k_standard.c \
	$(FDLIBM_SRC)/k_rem_pio2.c \
	$(FDLIBM_SRC)/k_cos.c \
	$(FDLIBM_SRC)/k_sin.c \
	$(FDLIBM_SRC)/k_tan.c \
	$(FDLIBM_SRC)/e_acos.c \
	$(FDLIBM_SRC)/e_acosh.c \
	$(FDLIBM_SRC)/e_asin.c \
	$(FDLIBM_SRC)/e_atan2.c \
	$(FDLIBM_SRC)/e_atanh.c \
	$(FDLIBM_SRC)/e_cosh.c \
	$(FDLIBM_SRC)/e_exp.c \
	$(FDLIBM_SRC)/e_fmod.c \
	$(FDLIBM_SRC)/e_gamma.c \
	$(FDLIBM_SRC)/e_gamma_r.c \
	$(FDLIBM_SRC)/e_hypot.c \
	$(FDLIBM_SRC)/e_j0.c \
	$(FDLIBM_SRC)/e_j1.c \
	$(FDLIBM_SRC)/e_jn.c \
	$(FDLIBM_SRC)/e_lgamma.c \
	$(FDLIBM_SRC)/e_lgamma_r.c \
	$(FDLIBM_SRC)/e_log.c \
	$(FDLIBM_SRC)/e_log10.c \
	$(FDLIBM_SRC)/e_pow.c \
	$(FDLIBM_SRC)/e_rem_pio2.c \
	$(FDLIBM_SRC)/e_remainder.c \
	$(FDLIBM_SRC)/e_scalb.c \
	$(FDLIBM_SRC)/e_sinh.c \
	$(FDLIBM_SRC)/e_sqrt.c \
	$(FDLIBM_SRC)/w_acos.c \
	$(FDLIBM_SRC)/w_acosh.c \
	$(FDLIBM_SRC)/w_asin.c \
	$(FDLIBM_SRC)/w_atan2.c \
	$(FDLIBM_SRC)/w_atanh.c \
	$(FDLIBM_SRC)/w_cosh.c \
	$(FDLIBM_SRC)/w_exp.c \
	$(FDLIBM_SRC)/w_fmod.c \
	$(FDLIBM_SRC)/w_gamma.c \
	$(FDLIBM_SRC)/w_gamma_r.c \
	$(FDLIBM_SRC)/w_hypot.c \
	$(FDLIBM_SRC)/w_j0.c \
	$(FDLIBM_SRC)/w_j1.c \
	$(FDLIBM_SRC)/w_jn.c \
	$(FDLIBM_SRC)/w_lgamma.c \
	$(FDLIBM_SRC)/w_lgamma_r.c \
	$(FDLIBM_SRC)/w_log.c \
	$(FDLIBM_SRC)/w_log10.c \
	$(FDLIBM_SRC)/w_pow.c \
	$(FDLIBM_SRC)/w_remainder.c \
	$(FDLIBM_SRC)/w_scalb.c \
	$(FDLIBM_SRC)/w_sinh.c \
	$(FDLIBM_SRC)/w_sqrt.c \
	$(FDLIBM_SRC)/s_asinh.c \
	$(FDLIBM_SRC)/s_atan.c \
	$(FDLIBM_SRC)/s_cbrt.c \
	$(FDLIBM_SRC)/s_ceil.c \
	$(FDLIBM_SRC)/s_copysign.c \
	$(FDLIBM_SRC)/s_tan.c \
	$(FDLIBM_SRC)/s_tanh.c \
	$(FDLIBM_SRC)/s_cos.c \
	$(FDLIBM_SRC)/s_erf.c \
	$(FDLIBM_SRC)/s_expm1.c \
	$(FDLIBM_SRC)/s_fabs.c \
	$(FDLIBM_SRC)/s_finite.c \
	$(FDLIBM_SRC)/s_floor.c \
	$(FDLIBM_SRC)/s_frexp.c \
	$(FDLIBM_SRC)/s_ilogb.c \
	$(FDLIBM_SRC)/s_isnan.c \
	$(FDLIBM_SRC)/s_ldexp.c \
	$(FDLIBM_SRC)/s_lib_version.c \
	$(FDLIBM_SRC)/s_log1p.c \
	$(FDLIBM_SRC)/s_logb.c \
	$(FDLIBM_SRC)/s_matherr.c \
	$(FDLIBM_SRC)/s_modf.c \
	$(FDLIBM_SRC)/s_rint.c \
	$(FDLIBM_SRC)/s_scalbn.c \
	$(FDLIBM_SRC)/s_signgam.c \
	$(FDLIBM_SRC)/s_significand.c \
	$(FDLIBM_SRC)/s_sin.c \
	$(FDLIBM_SRC)/s_nextafter.c \
	$(JAINJA_SRC)/tinygc/LP_Allocator.c \
	$(JAINJA_SRC)/tinygc/tinygc.c \
	$(JAINJA_SRC)/jainja/Main.c

OBJECTS := $(addsuffix .o, $(basename $(SOURCES)))

$(BINARY): $(OBJECTS)
	$(LD) -o $@ $(OBJECTS) $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<
