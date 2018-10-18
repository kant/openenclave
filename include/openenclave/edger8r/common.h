// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

/**
 * @file common.h
 *
 * This file defines the inline functions, macros and data-structures used in
 * oeedger8r generated code on both enclave and host side.
 * These internals are subject to change without notice.
 *
 */
#ifndef _OE_EDGER8R_COMMON_H
#define _OE_EDGER8R_COMMON_H

#include <openenclave/bits/defs.h>
#include <openenclave/bits/result.h>
#include <openenclave/bits/types.h>

OE_EXTERNC_BEGIN

/******************************************************************************/
/********* Macros and inline functions used by generated code *****************/
/******************************************************************************/

/**
 * Add a size value, rounding to sizeof(void*).
 */
OE_INLINE oe_result_t oe_add_size(size_t* total, size_t size)
{
    oe_result_t result = OE_FAILURE;
    size_t align = sizeof(void*);
    size_t sum = 0;

    // Round size to multiple of sizeof(void*)
    size_t rsize = ((size + align - 1) / align) * align;
    if (rsize < size)
    {
        result = OE_INTEGER_OVERFLOW;
        goto done;
    }

    // Add rounded-size and check for overlow.
    sum = *total + rsize;
    if (sum < *total)
    {
        result = OE_INTEGER_OVERFLOW;
        goto done;
    }

    *total = sum;
    result = OE_OK;

done:
    return result;
}

#define OE_ADD_SIZE(total, size)                \
    do                                          \
    {                                           \
        if (oe_add_size(&total, size) != OE_OK) \
        {                                       \
            _result = OE_INTEGER_OVERFLOW;      \
            goto done;                          \
        }                                       \
    } while (0)

/**
 * Compute and set the pointer value for the given parameter within the input
 * buffer. Make sure that the buffer has enough space.
 */
#define OE_SET_IN_POINTER(argname, argsize)                                  \
    if (pargs_in->argname)                                                   \
    {                                                                        \
        if ((input_buffer + input_buffer_offset + (size_t)(argsize)) >       \
            (input_buffer + input_buffer_size))                              \
        {                                                                    \
            _result = OE_BUFFER_TOO_SMALL;                                   \
            goto done;                                                       \
        }                                                                    \
        *(uint8_t**)&pargs_in->argname = input_buffer + input_buffer_offset; \
        OE_ADD_SIZE(input_buffer_offset, (size_t)(argsize));                 \
    }

#define OE_SET_IN_OUT_POINTER OE_SET_IN_POINTER

/**
 * Compute and set the pointer value for the given parameter within the output
 * buffer. Make sure that the buffer has enough space.
 */
#define OE_SET_OUT_POINTER(argname, argsize)                                   \
    if (pargs_in->argname)                                                     \
    {                                                                          \
        if ((output_buffer + output_buffer_offset + (size_t)(argsize)) >       \
            (output_buffer + output_buffer_size))                              \
        {                                                                      \
            _result = OE_BUFFER_TOO_SMALL;                                     \
            goto done;                                                         \
        }                                                                      \
        *(uint8_t**)&pargs_in->argname = output_buffer + output_buffer_offset; \
        OE_ADD_SIZE(output_buffer_offset, (size_t)(argsize));                  \
    }

/**
 * Compute and set the pointer value for the given parameter within the output
 * buffer. Make sure that the buffer has enough space.
 * Also copy the contents of the corresponding in-out pointer in the input
 * buffer.
 */
#define OE_COPY_AND_SET_IN_OUT_POINTER(argname, argsize)                       \
    if (pargs_in->argname)                                                     \
    {                                                                          \
        if ((output_buffer + output_buffer_offset + (size_t)(argsize)) >       \
            (output_buffer + output_buffer_size))                              \
        {                                                                      \
            _result = OE_BUFFER_TOO_SMALL;                                     \
            goto done;                                                         \
        }                                                                      \
        memcpy(                                                                \
            output_buffer + output_buffer_offset, pargs_in->argname, argsize); \
        *(uint8_t**)&pargs_in->argname = output_buffer + output_buffer_offset; \
        OE_ADD_SIZE(output_buffer_offset, (size_t)argsize);                    \
    }

/**
 * Copy an input parameter to input buffer.
 */
#define OE_WRITE_IN_PARAM(argname, size)                                   \
    if (argname)                                                           \
    {                                                                      \
        *(uint8_t**)&_args.argname = _input_buffer + _input_buffer_offset; \
        memcpy(_args.argname, argname, (size_t)(size));                    \
        OE_ADD_SIZE(_input_buffer_offset, (size_t)(size));                 \
    }

#define OE_WRITE_IN_OUT_PARAM OE_WRITE_IN_PARAM

/**
 * Read an output parameter from output buffer.
 */
#define OE_READ_OUT_PARAM(argname, size)                                      \
    if (argname)                                                              \
    {                                                                         \
        memcpy(                                                               \
            argname, _output_buffer + _output_buffer_offset, (size_t)(size)); \
        OE_ADD_SIZE(_output_buffer_offset, (size_t)(size));                   \
    }

#define OE_READ_IN_OUT_PARAM OE_READ_OUT_PARAM

OE_EXTERNC_END

#endif // _OE_EDGER8R_COMMON_H
