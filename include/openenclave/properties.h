// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

/**
 * \file properties.h
 *
 * This file defines enclave-property structures which are injected into
 * the following sections of the enclave image.
 *
 *     .oeinfo - injected by OE_SET_ENCLAVE_SGX (contains
 *               enclave properties with empty sigstructs)
 *     .oesign - injected by oesign tool (contains enclave properties with
 *               populated sigstructs)
 *
 * Since the .oeinfo section is measured during enclave loading, it cannot be
 * updated during signing (since the signed bits cannot contain the signature
 * itself).
 *
 * The enclave loader uses .oesign if it exists, else it falls back on .oeinfo.
 * If neither exist, loading fails.
 */

#ifndef _OE_PROPERTIES_H
#define _OE_PROPERTIES_H

#include <openenclave/defs.h>
#include <openenclave/types.h>

OE_EXTERNC_BEGIN

/* Injected by oesign utility */
#define OE_SIGN_SECTION_NAME ".oesign"

/* Injected by OE_SET_ENCLAVE_SGX macro */
#define OE_INFO_SECTION_NAME ".oeinfo"

/*
**==============================================================================
**
** OE_EnclavePropertiesHeader - generic enclave properties base type
**
**==============================================================================
*/

typedef enum _OE_EnclaveType { OE_ENCLAVE_TYPE_SGX } OE_EnclaveType;

typedef struct _OE_EnclaveSizeSettings
{
    uint64_t numHeapPages;
    uint64_t numStackPages;
    uint64_t numTCS;
} OE_EnclaveSizeSettings;

OE_CHECK_SIZE(sizeof(OE_EnclaveSizeSettings), 24);

/* Base type for enclave properties */
typedef struct _OE_EnclavePropertiesHeader
{
    /* (0) Size of the extended structure */
    uint32_t size;

    /* (4) Type of enclave (see OE_EnclaveType) */
    uint32_t enclaveType;

    /* (8) Type of enclave */
    OE_EnclaveSizeSettings sizeSettings;
} OE_EnclavePropertiesHeader;

OE_CHECK_SIZE(sizeof(OE_EnclavePropertiesHeader), 32);

/*
**==============================================================================
**
** OE_EnclaveProperties_SGX - SGX enclave properties derived type
**
**==============================================================================
*/

#define OE_SGX_KEY_SIZE 384
#define OE_SGX_EXPONENT_SIZE 4
#define OE_SGX_HASH_SIZE 32
#define OE_SGX_FLAGS_DEBUG 0x0000000000000002ULL
#define OE_SGX_FLAGS_MODE64BIT 0x0000000000000004ULL

/* OE_SGXSigStruct.header: 06000000E100000000000100H */
#define OE_SGX_SIGSTRUCT_HEADER \
    "\006\000\000\000\341\000\000\000\000\000\001\000"
#define OE_SGX_SIGSTRUCT_HEADER_SIZE (sizeof(OE_SGX_SIGSTRUCT_HEADER) - 1)

/* OE_SGXSigStruct.header2: 01010000600000006000000001000000H */
#define OE_SGX_SIGSTRUCT_HEADER2 \
    "\001\001\000\000\140\000\000\000\140\000\000\000\001\000\000\000"
#define OE_SGX_SIGSTRUCT_HEADER2_SIZE (sizeof(OE_SGX_SIGSTRUCT_HEADER2) - 1)

/* OE_SGXSigStruct.miscselect */
#define OE_SGX_SIGSTRUCT_MISCSELECT 0x00000000

/* OE_SGXSigStruct.miscmask */
#define OE_SGX_SIGSTRUCT_MISCMASK 0xffffffff

/* OE_SGXSigStruct.flags */
#define OE_SGX_SIGSTRUCT_ATTRIBUTEMASK_FLAGS 0Xfffffffffffffffd

/* OE_SGXSigStruct.xfrm */
#define OE_SGX_SIGSTRUCT_ATTRIBUTEMASK_XFRM 0xfffffffffffffffb

typedef struct _OE_SGXAttributes
{
    uint64_t flags;
    uint64_t xfrm;
} OE_SGXAttributes;

OE_CHECK_SIZE(sizeof(OE_SGXAttributes), 16);

typedef struct _OE_SGXSigStruct
{
    /* ======== HEADER-SECTION ======== */

    /* (0) must be (06000000E100000000000100H) */
    uint8_t header[12];

    /* (12) bit 31: 0 = prod, 1 = debug; Bit 30-0: Must be zero */
    uint32_t type;

    /* (16) Intel=0x8086, ISV=0x0000 */
    uint32_t vendor;

    /* (20) build date as yyyymmdd */
    uint32_t date;

    /* (24) must be (01010000600000006000000001000000H) */
    uint8_t header2[16];

    /* (40) For Launch Enclaves: HWVERSION != 0. Others, HWVERSION = 0 */
    uint32_t swdefined;

    /* (44) Must be 0 */
    uint8_t reserved[84];

    /* ======== KEY-SECTION ======== */

    /* (128) Module Public Key (keylength=3072 bits) */
    uint8_t modulus[OE_SGX_KEY_SIZE];

    /* (512) RSA Exponent = 3 */
    uint8_t exponent[OE_SGX_EXPONENT_SIZE];

    /* (516) Signature over Header and Body (HEADER-SECTION | BODY-SECTION) */
    uint8_t signature[OE_SGX_KEY_SIZE];

    /* ======== BODY-SECTION ======== */

    /* (900) The MISCSELECT that must be set */
    uint32_t miscselect;

    /* (904) Mask of MISCSELECT to enforce */
    uint32_t miscmask;

    /* (908) Reserved. Must be 0. */
    uint8_t reserved2[20];

    /* (928) Enclave Attributes that must be set */
    OE_SGXAttributes attributes;

    /* (944) Mask of Attributes to Enforce */
    OE_SGXAttributes attributemask;

    /* (960) MRENCLAVE - (32 bytes) */
    uint8_t enclavehash[OE_SGX_HASH_SIZE];

    /* (992) Must be 0 */
    uint8_t reserved3[32];

    /* (1024) ISV assigned Product ID */
    uint16_t isvprodid;

    /* (1026) ISV assigned SVN */
    uint16_t isvsvn;

    /* ======== BUFFER-SECTION ======== */

    /* (1028) Must be 0 */
    uint8_t reserved4[12];

    /* (1040) Q1 value for RSA Signature Verification */
    uint8_t q1[OE_SGX_KEY_SIZE];

    /* (1424) Q2 value for RSA Signature Verification */
    uint8_t q2[OE_SGX_KEY_SIZE];
} OE_SGXSigStruct;

OE_CHECK_SIZE(sizeof(OE_SGXSigStruct), 1808);

OE_CHECK_SIZE(
    sizeof((OE_SGXSigStruct*)NULL)->header,
    OE_SGX_SIGSTRUCT_HEADER_SIZE);

OE_CHECK_SIZE(
    sizeof((OE_SGXSigStruct*)NULL)->header2,
    OE_SGX_SIGSTRUCT_HEADER2_SIZE);

typedef struct _OE_SGX_EnclaveSettings
{
    uint16_t productID;
    uint16_t securityVersion;

    /* Padding to make packed and unpacked size the same */
    uint32_t padding;

    /* (SGX_FLAGS_DEBUG | SGX_FLAGS_MODE64BIT) */
    uint64_t attributes;
} OE_SGXEnclaveSettings;

OE_CHECK_SIZE(sizeof(OE_SGXEnclaveSettings), 16);

/* Extends OE_EnclavePropertiesHeader base type */
typedef struct _OE_EnclaveProperties_SGX
{
    /* (0) */
    OE_EnclavePropertiesHeader header;

    /* (32) */
    OE_SGXEnclaveSettings settings;

    /* (48) */
    OE_SGXSigStruct sigstruct;
} OE_EnclaveProperties_SGX;

OE_CHECK_SIZE(sizeof(OE_EnclaveProperties_SGX), 1856);

/*
**==============================================================================
**
** OE_SET_ENCLAVE_SGX:
**     This macro initializes and injects an OE_EnclaveProperties_SGX struct
**     into the .oeinfo section.
**
**==============================================================================
*/

#define OE_INFO_SECTION_BEGIN __attribute__((section(OE_INFO_SECTION_NAME)))
#define OE_INFO_SECTION_END

#define OE_MAKE_ATTRIBUTES(_AllowDebug_) \
    (OE_SGX_FLAGS_MODE64BIT | (_AllowDebug_ ? OE_SGX_FLAGS_DEBUG : 0))

// Note: disable clang-format since it badly misformats this macro
// clang-format off

#define OE_SET_ENCLAVE_SGX(                       \
    _ProductID_,                                                \
    _SecurityVersion_,                                          \
    _AllowDebug_,                                               \
    _HeapPageCount_,                                            \
    _StackPageCount_,                                           \
    _TcsCount_)                                                 \
    OE_INFO_SECTION_BEGIN                                       \
    const OE_EnclaveProperties_SGX oe_enclavePropertiesSGX =    \
    {                                                           \
        .header =                                               \
        {                                                       \
            .size = sizeof(OE_EnclaveProperties_SGX),           \
            .enclaveType = OE_ENCLAVE_TYPE_SGX,                 \
            .sizeSettings =                                     \
            {                                                   \
                .numHeapPages = _HeapPageCount_,                \
                .numStackPages = _StackPageCount_,              \
                .numTCS = _TcsCount_                            \
            }                                                   \
        },                                                      \
        .settings =                                             \
        {                                                       \
            .productID = _ProductID_,                           \
            .securityVersion = _SecurityVersion_,               \
            .padding = 0,                                       \
            .attributes = OE_MAKE_ATTRIBUTES(_AllowDebug_)      \
        },                                                      \
        .sigstruct =                                            \
        {                                                       \
            .header = { 0 },                                    \
        }                                                       \
    };                                                          \
    OE_INFO_SECTION_END

// clang-format on

OE_EXTERNC_END

#endif /* _OE_PROPERTIES_H */
