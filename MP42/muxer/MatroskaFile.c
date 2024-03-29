/*
 *  MatroskaFile.c
 *  Subler
 *
 *  Created by Ryan Walklin on 23/09/09.
 *  Copyright 2009 Test Toast. All rights reserved.
 *
 */

#include <stdlib.h> 
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>

#include "MatroskaParser.h"
#include "MatroskaFile.h"

#pragma mark Parser callbacks

#define CACHESIZE 0xFFFFFFF

/* StdIoStream methods */ 

/* read count bytes into buffer starting at file position pos 
 * return the number of bytes read, -1 on error or 0 on EOF 
 */ 
int StdIoRead(StdIoStream *st, uint64_t pos, void *buffer, int count) { 
	size_t  rd; 
	if (fseeko(st->fp, pos, SEEK_SET) == -1) { 
		st->error = errno; 
		return -1; 
	} 
	rd = fread(buffer, 1, count, st->fp); 
	if (rd == 0) { 
		if (feof(st->fp)) 
			return 0; 
		st->error = errno; 
		return -1; 
	} 
	return (int)rd;
} 

/* scan for a signature sig(big-endian) starting at file position pos 
 * return position of the first byte of signature or -1 if error/not found 
 */ 
longlong StdIoScan(StdIoStream *st, uint64_t start, uint32_t signature) { 
	uint32_t         c; 
	uint32_t    cmp = 0; 
	FILE              *fp = st->fp; 

	if (fseeko(fp, start, SEEK_SET)) 
		return -1; 

	while ((c = getc(fp)) != EOF) { 
		cmp = ((cmp << 8) | c) & 0xffffffff; 
		if (cmp == signature) 
			return ftell(fp) - 4; 
	} 

	return -1; 
} 

/* return cache size, this is used to limit readahead */ 
unsigned StdIoGetCacheSize(StdIoStream *st) { 
	return CACHESIZE; 
}

/* return last error message */ 
const char *StdIoGetLastError(StdIoStream *st) { 
	return strerror(st->error); 
} 

/* memory allocation, this is done via stdlib */ 
void  *StdIoMalloc(StdIoStream *st, size_t size) { 
	return malloc(size); 
} 

void  *StdIoRealloc(StdIoStream *st, void *mem, size_t size) { 
	return realloc(mem,size); 
} 

void  StdIoFree(StdIoStream *st, void *mem) { 
	free(mem); 
} 

/* progress report handler for lengthy operations 
 * returns 0 to abort operation, nonzero to continue 
 */ 
int StdIoProgress(StdIoStream *st, uint64_t cur, uint64_t max) { 
	return 1; 
} 

MatroskaFile *openMatroskaFile(const char *filePath, StdIoStream *ioStream)
{
	char err_msg[256];

	/* fill in I/O object */ 
	ioStream->base.read = (int(*)(struct InputStream *, ulonglong, void *, int))StdIoRead;
	ioStream->base.scan = (longlong(*)(struct InputStream *, ulonglong, unsigned int))StdIoScan;
	ioStream->base.getcachesize = (unsigned int (*)(struct InputStream *))StdIoGetCacheSize; 
	ioStream->base.geterror = (const char *(*)(struct InputStream *))StdIoGetLastError;
	ioStream->base.memalloc = (void *(*)(struct InputStream *, size_t))StdIoMalloc;
	ioStream->base.memrealloc = (void *(*)(struct InputStream *, void *, size_t))StdIoRealloc;
	ioStream->base.memfree = (void(*)(struct InputStream *, void *))StdIoFree;
	ioStream->base.progress = (int (*)(struct InputStream *, uint64_t, uint64_t))StdIoProgress;

	/* open source file */ 
	ioStream->fp = fopen(filePath,"r");
	if (ioStream->fp == NULL) { 
		fprintf(stderr, "Can't open '%s': %s\n", filePath, strerror(errno)); 
		return NULL; 
	}

    /* Disable ram cache */
    //fcntl (ioStream->fp->_file, F_RDAHEAD, 1);
    //fcntl (ioStream->fp->_file, F_NOCACHE, 1);

	/* initialize matroska parser */ 
	MatroskaFile *mf = mkv_Open(&ioStream->base, /* pointer to I/O object */ 
                                err_msg, sizeof(err_msg)); /* error message is returned here */ 

	if (mf == NULL) {
		fclose(ioStream->fp); 
		fprintf(stderr, "Can't parse Matroska file: %s\n", err_msg); 
		return NULL; 
	} 

	return mf;	
}

void closeMatroskaFile(MatroskaFile *matroskaFile, StdIoStream *ioStream)
{
    /* close matroska parser */
	mkv_Close(matroskaFile);
    
	/* close file */
    if (ioStream) {
        fclose(ioStream->fp);
        free(ioStream);
    }
}
