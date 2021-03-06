// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once

#include <wchar.h>

// Assert that given arguments are of specified types.
// Results in compile error on type mismatch.
template <typename... Args>
void check_type(Args&...)
{
}

// Check the type of _retval field of a given args type.
template <typename args_type, typename R>
void check_return_type()
{
    args_type args;
    check_type<R>(args._retval);
}

template <int N>
struct unused
{
    unused(int i = 0)
    {
    }
};

// Ensure that the given field does not exist
// in given marshaling struct.
// If the field exists, an ambiguous call compiler
// error will occur.

#define DEFINE_ASSERT_NO_FIELD(fname)                            \
    template <typename S>                                        \
    void assert_no_field_##fname(unused<sizeof(S::fname)> u = 0) \
    {                                                            \
    }                                                            \
    template <typename S>                                        \
    void assert_no_field_##fname()                               \
    {                                                            \
    }

DEFINE_ASSERT_NO_FIELD(s_len)

template <typename T, int N, typename U>
inline int array_compare(const T (&a1)[N], U u)
{
    const T* a2 = (const T*)u;
    for (int i = 0; i < N; ++i)
    {
        if (a1[i] < a2[i])
            return -1;
        else if (a1[i] > a2[i])
            return 1;
    }
    return 0;
}

const wchar_t ohm = L'\u2126';
