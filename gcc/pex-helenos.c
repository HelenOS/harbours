/*
 * Copyright (c) 2013 Vojtech Horky
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 * - The name of the author may not be used to endorse or promote products
 *   derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef __helenos__
#include "pex-unix.c"
#else

#include "config.h"
#include "libiberty.h"
#include "pex-common.h"

#include <libc/task.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <limits.h>

/*
 * Implementation of the individual operations.
 */

static int pex_helenos_open_read(struct pex_obj *obj ATTRIBUTE_UNUSED,
    const char *name, int binary ATTRIBUTE_UNUSED)
{
	return open(name, O_RDONLY);
}

static int pex_helenos_open_write(struct pex_obj *obj ATTRIBUTE_UNUSED,
    const char *name, int binary ATTRIBUTE_UNUSED)
{
	return open(name, O_WRONLY | O_CREAT | O_TRUNC);
}

static int pex_helenos_close(struct pex_obj *obj ATTRIBUTE_UNUSED, int fd)
{
	return close(fd);
}

static pid_t pex_helenos_exec_child(struct pex_obj *obj ATTRIBUTE_UNUSED,
    int flags ATTRIBUTE_UNUSED,
    const char *executable, char * const * argv,
    char * const * env ATTRIBUTE_UNUSED,
    int in, int out, int errdes,
    int toclose ATTRIBUTE_UNUSED,
    const char **errmsg, int *err)
{
	int *files[4];
	files[0] = &in;
	files[1] = &out;
	files[2] = &errdes;
	files[3] = NULL;
	
	task_id_t task_id = 0;
	char  full_path[1024];
	// FIXME: decide on paths
	snprintf(full_path, 1023, "/app/%s", executable);
	int rc = task_spawnvf(&task_id, full_path, argv, files);
	
	if (rc != 0) {
		*err = rc;
		*errmsg = "task_spawnvf";
		return (pid_t) -1;
	}
	
	return (pid_t) task_id;
}

static int pex_helenos_wait(struct pex_obj *obj ATTRIBUTE_UNUSED,
    pid_t pid, int *status,
    struct pex_time *time, int done,
    const char **errmsg, int *err)
{
	/*
	 * If @c done is set, we are cleaning-up. Kill the process
	 * mercilessly.
	 */
	if (done) {
		task_kill( (task_id_t) pid);
	}
	
	if (time != NULL) {
		memset(time, 0, sizeof(*time));
	}
	
	task_exit_t task_exit;
	int task_retval;
	int rc = task_wait((task_id_t) pid, &task_exit, &task_retval);
	if (rc != 0) {
		*err = -rc;
		*errmsg = "task_wait";
		*status = -rc;
		return -1;
	} else {
		if (task_exit == TASK_EXIT_UNEXPECTED) {
			*status = INT_MIN;
			return -1;
		} else {
			*status = task_retval;
			return 0;
		}
	}
}


/*
 * PEX initialization.
 */

const struct pex_funcs funcs = {
	pex_helenos_open_read,
	pex_helenos_open_write,
	pex_helenos_exec_child,
	pex_helenos_close,
	pex_helenos_wait,
	NULL,
	NULL,
	NULL,
	NULL
};

struct pex_obj *pex_init(int flags, const char *pname, const char *tempbase)
{
	return pex_init_common(flags, pname, tempbase, &funcs);
}

#endif
