#!/usr/bin/env python3

#
# Copyright (c) 2017 Vojtech Horky
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

# https://gcc.gnu.org/onlinedocs/gcc/Spec-Files.html
#
# Usage: prog base-path CFLAGS -- ASFLAGS -- LDFLAGS

import sys
import re

def args_to_dict(args):
    i = 0
    result = {}
    ordering = []
    while i < len(args):
        if args[i] in [ '-I', '-imacros', '-T' ]:
            ordering.append(args[i])
            result[ args[i] ] = args[i + 1]
            i = i + 2
        else:
            ordering.append(args[i])
            result[ args[i] ] = None
            i = i + 1
    return ( ordering, result )

base_path = sys.argv[1]
cflags_args = []
asmflags_args = []
ldflags_args = []

i = 2
while i < len(sys.argv):
    if sys.argv[i] == '--':
        i = i + 1
        break
    cflags_args.append(sys.argv[i])
    i = i + 1
while i < len(sys.argv):
    if sys.argv[i] == '--':
        i = i + 1
        break
    asmflags_args.append(sys.argv[i])
    i = i + 1
while i < len(sys.argv):
    if sys.argv[i] == '--':
        break
    ldflags_args.append(sys.argv[i])
    i = i + 1


( cflags_ordering, cflags ) = args_to_dict(cflags_args)
( asmflags_ordering, asmflags ) = args_to_dict(asmflags_args)
( ldflags_ordering, ldflags ) = args_to_dict(ldflags_args)

spec_directives = {
    '*asm': [ "+ " ],
    '*helenos_flags_charset': [],
    '*cpp_unique_options': [ "+ ", "-D__helenos__", "-D__HELENOS__", "-imacros _bits/macros.h" ],
    '*cpp': [ "+ %(helenos_flags_charset)" ],
    '*libgcc': [],
    '*startfile': [],
    '*endfile': [],
    '*cc1': [ "+ %(helenos_flags_charset)" ],
    '*cross_compile': [ '1' ],
    '*link': [],
}

charset_flags = re.compile('^-f.*charset.*=')
optim_flag = re.compile('^-O[0123s]$')

extra_asm_flags = [ '-march=4kc', '-march=r4000' ]

for flag in cflags_ordering:
    if (flag == '-pipe') or (optim_flag.match(flag) is not None) or flag.startswith("-W"):
        pass
    elif charset_flags.match(flag) is not None:
        spec_directives['*helenos_flags_charset'].append(flag)
    elif flag == '-imacros':
        # Skip the config.h file altogether
        # FIXME: check that no macros from that file are used in the headers!
        pass
    elif flag.startswith("-I"):
        include_path = flag[2:]
        if include_path.startswith(base_path):
            spec_directives['*cpp_unique_options'].append(flag)
    elif flag.startswith("-D"):
        spec_directives['*cpp_unique_options'].append(flag)
    elif flag == '-nostdlib':
        spec_directives['*link'].append(flag)
    elif flag == '-nostdinc':
        spec_directives['*cpp_unique_options'].append(flag)
    else:
        full_flag = flag if cflags[flag] is None else flag + " " + cflags[flag]
        spec_directives['*cc1'].append(full_flag)
        
        # Some flags needs to be passed to the assembler too
        if flag in extra_asm_flags:
            spec_directives['*asm'].append(full_flag)


for flag in asmflags_ordering:
    if flag == '--fatal-warnings':
        continue
    full_flag = flag if asmflags[flag] is None else flag + " " + asmflags[flag]
    spec_directives['*asm'].append(full_flag)


for flag in ldflags_ordering:
    if flag == '--fatal-warnings':
        continue
    full_flag = flag if ldflags[flag] is None else flag + " " + ldflags[flag]
    spec_directives['*link'].append(full_flag)


for spec_name in sorted(spec_directives):
    print("{}:\n{}\n".format(spec_name, " \\\n".join(spec_directives[spec_name])))

