// SPDX-License-Identifier: GPL-3.0-or-later
/* aubio 0.4.9 build configuration for vChain: what Homebrew's macOS build defines (waf configure on macOS), minus
 * libsndfile and file I/O, which vChain doesn't use (test files are read with ExtAudioFile). FFT through Accelerate
 * (vDSP), single precision, memcpy hacks, release (NDEBUG). */
#ifndef AUBIO_CONFIG_H
#define AUBIO_CONFIG_H
#define HAVE_STDLIB_H 1
#define HAVE_STDIO_H 1
#define HAVE_MATH_H 1
#define HAVE_STRING_H 1
#define HAVE_ERRNO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STDARG_H 1
#define HAVE_C99_VARARGS_MACROS 1
#define HAVE_MEMCPY_HACKS 1
#define HAVE_ACCELERATE 1
#ifndef NDEBUG
#define NDEBUG 1
#endif
#endif
