#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tss2/tss2_esys.h>
#include <tss2/tss2_mu.h>
#include <tss2/tss2_rc.h>

#include "lib.h"

#define ASN1_SEQ 0x30
#define ASN1_INT 0x02
#define ASN1_OID 0x06
#define ASN1_BitString 0x03
#define PRIME_LEN 32
#define ANS1_MAX_KEY_SIZE 4 + 9 + 10 + 4 + PRIME_LEN + PRIME_LEN

#define NV_INDEX 0x1880001

static ESYS_CONTEXT *esysContext;
int rc;

static ESYS_TR rootKeyHandle;
static BYTE rootKeyASN[ANS1_MAX_KEY_SIZE];
static INT rootKeySizeASN;
static BYTE rootKeyHash[PRIME_LEN];

static ESYS_TR previousKeyHandle;
static BYTE previousKeyASN[ANS1_MAX_KEY_SIZE];
static INT previousKeySizeASN;
static INT previousKeyIndex;

static ESYS_TR nextKeyHandle;
static BYTE nextKeyASN[ANS1_MAX_KEY_SIZE];
static INT nextKeySizeASN;
static INT nextKeyIndex;

static ESYS_TR currentKeyHandle;
static TPM2B_PUBLIC *currentKeyTPM = NULL;
static BYTE currentKeyASN[ANS1_MAX_KEY_SIZE];
static INT currentKeySizeASN;

static BYTE tempKey[ANS1_MAX_KEY_SIZE];
static BYTE sigEccASN[2 + 2 + PRIME_LEN + 2 + PRIME_LEN + 2];
static BYTE zPoint[2 * PRIME_LEN + 1];

void keyToASN() {
  BYTE asnHeader[] = {ASN1_SEQ, 0x59, ASN1_SEQ, 0x13};
  BYTE keyType[] = {ASN1_OID, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01};
  BYTE curveType[] = {ASN1_OID, 0x08, 0x2a, 0x86, 0x48,
                      0xce,     0x3d, 0x03, 0x01, 0x07};
  BYTE pubKeyHeader[] = {ASN1_BitString, 0x42, 0x00, 0x04};

  int index = 0, size_x_y = 0;
  memcpy(currentKeyASN + index, asnHeader, sizeof(asnHeader));
  index += sizeof(asnHeader);

  memcpy(currentKeyASN + index, keyType, sizeof(keyType));
  index += sizeof(keyType);

  memcpy(currentKeyASN + index, curveType, sizeof(curveType));
  index += sizeof(curveType);

  memcpy(currentKeyASN + index, pubKeyHeader, sizeof(pubKeyHeader));
  index += sizeof(pubKeyHeader);

  size_x_y = currentKeyTPM->publicArea.unique.ecc.x.size;
  memcpy(currentKeyASN + index, currentKeyTPM->publicArea.unique.ecc.x.buffer,
         size_x_y);
  index += size_x_y;

  size_x_y = currentKeyTPM->publicArea.unique.ecc.y.size;
  memcpy(currentKeyASN + index, currentKeyTPM->publicArea.unique.ecc.y.buffer,
         size_x_y);
  index += size_x_y;

  currentKeySizeASN = index;
  // Esys_Free(currentKeyTPM);
}

void signToASN(BYTE *r, INT sizeR, BYTE *s, INT sizeS, INT *asnSignSize) {

  int index = 0;
  sigEccASN[index++] = ASN1_SEQ;

  int asnLen = (PRIME_LEN * 2) + 4;
  if (r[0] > 127) { // check MSB, R needs padding to remain positive
    asnLen++;
  }
  if (s[0] > 127) { // check MSB, S needs padding to remain positive
    asnLen++;
  }
  /*
      if(asnLen > 127)
              sigEccASN[index++] = 0x81;
  */
  sigEccASN[index++] = asnLen;

  // R value
  sigEccASN[index++] = ASN1_INT;
  if (r[0] > 127) {
    sigEccASN[index++] = PRIME_LEN + 1;
    sigEccASN[index++] = 0x00; // Extra byte to ensure R remains positive
  } else {
    sigEccASN[index++] = PRIME_LEN;
  }
  memcpy(sigEccASN + index, r, PRIME_LEN);
  index += PRIME_LEN;

  // S value
  sigEccASN[index++] = ASN1_INT;
  if (s[0] > 127) {
    sigEccASN[index++] = PRIME_LEN + 1;
    sigEccASN[index++] = 0x00; // Extra byte to ensure S remains positive
  } else {
    sigEccASN[index++] = PRIME_LEN;
  }
  memcpy(sigEccASN + index, s, PRIME_LEN);
  index += PRIME_LEN;

  *asnSignSize = index;

  // return sigEccASN;
}

void generatePublicKey(INT keyIndex) {
  TPM2B_SENSITIVE_CREATE inSensitive = {
      .size = 0,
      .sensitive = {.userAuth =
                        {
                            .size = 0,
                            .buffer = {0},
                        },
                    .data = {.size = 0, .buffer = {0}}}};

  TPM2B_PUBLIC inPublicECC = {
      .size = 0,
      .publicArea = {
          .type = TPM2_ALG_ECC,
          .nameAlg = TPM2_ALG_SHA256,

          .objectAttributes =
              (TPMA_OBJECT_USERWITHAUTH | TPMA_OBJECT_ADMINWITHPOLICY |
               TPMA_OBJECT_SIGN_ENCRYPT | TPMA_OBJECT_DECRYPT |
               TPMA_OBJECT_FIXEDTPM | TPMA_OBJECT_FIXEDPARENT |
               TPMA_OBJECT_SENSITIVEDATAORIGIN),

          .authPolicy = {.size = 32,
                         .buffer = {0x83, 0x71, 0x97, 0x67, 0x44, 0x84, 0xB3,
                                    0xF8, 0x1A, 0x90, 0xCC, 0x8D, 0x46, 0xA5,
                                    0xD7, 0x24, 0xFD, 0x52, 0xD7, 0x6E, 0x06,
                                    0x52, 0x0B, 0x64, 0xF2, 0xA1, 0xDA, 0x1B,
                                    0x33, 0x14, 0x69, 0xAA}},
          .parameters.eccDetail =
              {.symmetric =
                   {
                       .algorithm = TPM2_ALG_NULL,
                       .keyBits.aes = 256,
                       .mode.sym = TPM2_ALG_CFB,
                   },
               .scheme = {.scheme = TPM2_ALG_NULL,
                          .details = {.ecdsa = {.hashAlg = TPM2_ALG_SHA256}}},
               .curveID = TPM2_ECC_NIST_P256,
               .kdf = {.scheme = TPM2_ALG_NULL, .details = {}}},
          .unique.ecc = {.x = {.size = 32, .buffer = {0}},
                         .y = {.size = 32, .buffer = {0}}},

      }};

  memcpy(inPublicECC.publicArea.unique.ecc.x.buffer, rootKeyHash, 32);
  memcpy(inPublicECC.publicArea.unique.ecc.y.buffer, &keyIndex,
         sizeof(keyIndex));

  TPM2B_DATA outsideInfo = {
      .size = 0,
      .buffer = {},
  };

  TPML_PCR_SELECTION creationPCR = {
      .count = 0,
  };

  TPM2B_CREATION_DATA *creationData = NULL;
  TPM2B_DIGEST *creationHash = NULL;
  TPMT_TK_CREATION *creationTicket = NULL;

  rc = Esys_CreatePrimary(esysContext, ESYS_TR_RH_ENDORSEMENT, ESYS_TR_PASSWORD,
                          ESYS_TR_NONE, ESYS_TR_NONE, &inSensitive,
                          &inPublicECC, &outsideInfo, &creationPCR,
                          &currentKeyHandle, &currentKeyTPM, &creationData,
                          &creationHash, &creationTicket);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Primary Key Creation Failed -> %s\n", Tss2_RC_Decode(rc));
    exit(1);
  }

  Esys_Free(creationData);
  Esys_Free(creationHash);
  Esys_Free(creationTicket);

  keyToASN();
  if (keyIndex) {
    Esys_Free(currentKeyTPM);
  }
}

void setRootKey() {
  memset(rootKeyASN, 0, ANS1_MAX_KEY_SIZE);
  memset(rootKeyHash, 0, PRIME_LEN);
  generatePublicKey(0);

  rootKeySizeASN = currentKeySizeASN;
  memcpy(rootKeyASN, currentKeyASN, currentKeySizeASN);
  rootKeyHandle = currentKeyHandle;

  TPM2B_MAX_BUFFER data = {.size = 64, .buffer = {}};
  memcpy(data.buffer, (*currentKeyTPM).publicArea.unique.ecc.x.buffer, 32);
  memcpy(data.buffer + 32, (*currentKeyTPM).publicArea.unique.ecc.y.buffer, 32);

  TPMT_TK_HASHCHECK *hashTicket = NULL;
  TPM2B_DIGEST *creationHash = NULL;

  Esys_Hash(esysContext, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &data,
            TPM2_ALG_SHA256, ESYS_TR_RH_OWNER, &creationHash, &hashTicket);
  memcpy(rootKeyHash, creationHash, 32);

  Esys_Free(hashTicket);
  Esys_Free(creationHash);
  Esys_Free(currentKeyTPM);
}

void updateHandlesIndexes() {
  Esys_FlushContext(esysContext, previousKeyHandle);
  previousKeyHandle = nextKeyHandle;
  previousKeyIndex = nextKeyIndex;
  memset(previousKeyASN, 0, ANS1_MAX_KEY_SIZE);
  memcpy(previousKeyASN, nextKeyASN, nextKeySizeASN);
  previousKeySizeASN = nextKeySizeASN;

  nextKeyIndex = previousKeyIndex + 1;
  generatePublicKey(nextKeyIndex);
  nextKeyHandle = currentKeyHandle;
  memset(nextKeyASN, 0, ANS1_MAX_KEY_SIZE);
  memcpy(nextKeyASN, currentKeyASN, currentKeySizeASN);
  nextKeySizeASN = currentKeySizeASN;
}

void setKeyIndex(INT keyIndex) {
  if (keyIndex < 1) {
    keyIndex = 1;
  }
  previousKeyIndex = keyIndex;
  if (previousKeyHandle != ESYS_TR_NONE) {
    Esys_FlushContext(esysContext, previousKeyHandle);
  }
  generatePublicKey(previousKeyIndex);
  previousKeyHandle = currentKeyHandle;
  previousKeySizeASN = currentKeySizeASN;

  memset(previousKeyASN, 0, ANS1_MAX_KEY_SIZE);
  memcpy(previousKeyASN, currentKeyASN, currentKeySizeASN);

  nextKeyIndex = previousKeyIndex + 1;
  if (nextKeyHandle != ESYS_TR_NONE) {
    Esys_FlushContext(esysContext, nextKeyHandle);
  }
  generatePublicKey(nextKeyIndex);
  nextKeyHandle = currentKeyHandle;
  nextKeySizeASN = currentKeySizeASN;

  memset(nextKeyASN, 0, ANS1_MAX_KEY_SIZE);
  memcpy(nextKeyASN, currentKeyASN, currentKeySizeASN);

  currentKeyHandle = ESYS_TR_NONE;
}

void provisionNodeSeed() {
  ESYS_TR session = ESYS_TR_NONE;
  TPMT_SYM_DEF symmetric = {.algorithm = TPM2_ALG_AES,
                            .keyBits = {.aes = 128},
                            .mode = {.aes = TPM2_ALG_CFB}};

  rc = Esys_StartAuthSession(
      esysContext, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
      ESYS_TR_NONE, NULL, TPM2_SE_HMAC, &symmetric, TPM2_ALG_SHA256, &session);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Start session -> %s \n", Tss2_RC_Decode(rc));
    exit(1);
  }

  rc = Esys_TRSess_SetAttributes(esysContext, session,
                                 TPMA_SESSION_DECRYPT | TPMA_SESSION_ENCRYPT |
                                     TPMA_SESSION_CONTINUESESSION,
                                 0xff);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Set session attributes -> %s\n", Tss2_RC_Decode(rc));
    exit(1);
  }

  // Search the NV index
  TPMS_CAPABILITY_DATA *capability_data = NULL;
  rc =
      Esys_GetCapability(esysContext, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                         TPM2_CAP_HANDLES, NV_INDEX, 1, NULL, &capability_data);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Get capability -> %s \n", Tss2_RC_Decode(rc));
    exit(1);
  }

  int exists = (capability_data->data.handles.count > 0 &&
                capability_data->data.handles.handle[0] == NV_INDEX);
  if (exists == 1) {
    return;
  }

  ESYS_TR nvHandle = ESYS_TR_NONE;

  TPM2B_NV_PUBLIC publicInfo = {
      .size = sizeof(publicInfo.nvPublic),
      .nvPublic = {.attributes = TPM2_NT_ORDINARY | TPMA_NV_WRITEALL |
                                 TPMA_NV_AUTHWRITE | TPMA_NV_POLICYREAD |
                                 TPMA_NV_AUTHREAD | TPMA_NV_OWNERREAD,
                   .dataSize = 32,
                   .nameAlg = TPM2_ALG_SHA256,
                   .nvIndex = NV_INDEX,
                   .authPolicy = {.size = 0, .buffer = {}}}};

  TPM2B_AUTH nullAuth = {.size = 0};

  // Create the NV index
  rc = Esys_NV_DefineSpace(esysContext, ESYS_TR_RH_OWNER, session, ESYS_TR_NONE,
                           ESYS_TR_NONE, &nullAuth, &publicInfo, &nvHandle);

  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: NV Define -> %s \n", Tss2_RC_Decode(rc));
    exit(1);
  }

  // Generate random bytes
  TPM2B_DIGEST *seed;
  rc = Esys_GetRandom(esysContext, session, ESYS_TR_NONE, ESYS_TR_NONE, 32,
                      &seed);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Get random after session -> %s \n", Tss2_RC_Decode(rc));
    exit(1);
  }

  // Write the bytes to the NV index
  rc = Esys_NV_Write(esysContext, nvHandle, nvHandle, session, ESYS_TR_NONE,
                     ESYS_TR_NONE, (TPM2B_MAX_NV_BUFFER *)seed, 0);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: NV Write -> %s \n", Tss2_RC_Decode(rc));
    exit(1);
  }

  Esys_Free(seed);

  rc = Esys_FlushContext(esysContext, session);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Context flushing -> %s \n", Tss2_RC_Decode(rc));
    exit(1);
  }
}

void initializeTPM(INT keyIndex) {
  rc = Esys_Initialize(&esysContext, NULL, NULL);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Esys Initialization Failed -> %s\n", Tss2_RC_Decode(rc));
    exit(1);
  }

  previousKeyHandle = ESYS_TR_NONE;
  nextKeyHandle = ESYS_TR_NONE;
  setRootKey();
  setKeyIndex(keyIndex);
  provisionNodeSeed();
}

BYTE *getPublicKey(INT keyIndex, INT *publicKeySize) {
  if (keyIndex == nextKeyIndex) {
    memcpy(publicKeySize, &nextKeySizeASN, sizeof(nextKeySizeASN));
    return nextKeyASN;
  } else if (keyIndex == previousKeyIndex) {
    memcpy(publicKeySize, &previousKeySizeASN, sizeof(previousKeySizeASN));
    return previousKeyASN;
  } else if (keyIndex == 0) {
    memcpy(publicKeySize, &rootKeySizeASN, sizeof(rootKeySizeASN));
    return rootKeyASN;
  } else {
    Esys_FlushContext(esysContext, rootKeyHandle);
    generatePublicKey(keyIndex);
    Esys_FlushContext(esysContext, currentKeyHandle);

    memcpy(tempKey, currentKeyASN, currentKeySizeASN);
    memcpy(publicKeySize, &currentKeySizeASN, sizeof(currentKeySizeASN));

    setRootKey();
    return tempKey;
  }
}

BYTE *signECDSA(INT keyIndex, BYTE *hashToSign, INT *eccSignSize,
                bool increment) {

  TPM2B_DIGEST hashTPM = {.size = 32};
  memcpy(hashTPM.buffer, hashToSign, 32);

  TPMT_SIG_SCHEME inScheme = {
      .scheme = TPM2_ALG_ECDSA,
      .details = {.ecdsa = {.hashAlg = TPM2_ALG_SHA256}}};

  TPMT_TK_HASHCHECK hash_validation = {.tag = TPM2_ST_HASHCHECK,
                                       .hierarchy = TPM2_RH_ENDORSEMENT,
                                       .digest = {0}};

  TPMT_SIGNATURE *signature = NULL;

  ESYS_TR signingKeyHandle = ESYS_TR_NONE;

  if (keyIndex == 0) {
    signingKeyHandle = rootKeyHandle;
  } else if (keyIndex != previousKeyIndex) {
    setKeyIndex(keyIndex);
    signingKeyHandle = previousKeyHandle;
  } else {
    signingKeyHandle = previousKeyHandle;
  }

  rc = Esys_Sign(esysContext, signingKeyHandle, ESYS_TR_PASSWORD, ESYS_TR_NONE,
                 ESYS_TR_NONE, &hashTPM, &inScheme, &hash_validation,
                 &signature);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Signing failed -> %s\n", Tss2_RC_Decode(rc));
    exit(1);
  }
  if (keyIndex && increment) {
    updateHandlesIndexes();
  }

  INT asnSignSize = 0;
  signToASN(signature->signature.ecdsa.signatureR.buffer,
            signature->signature.ecdsa.signatureR.size,
            signature->signature.ecdsa.signatureS.buffer,
            signature->signature.ecdsa.signatureS.size, &asnSignSize);
  memcpy(eccSignSize, &asnSignSize, sizeof(asnSignSize));
  Esys_Free(signature);
  return sigEccASN;
}

BYTE *retrieveNodeSeed() {
  ESYS_TR session = ESYS_TR_NONE;
  TPMT_SYM_DEF symmetric = {.algorithm = TPM2_ALG_AES,
                            .keyBits = {.aes = 128},
                            .mode = {.aes = TPM2_ALG_CFB}};

  rc = Esys_StartAuthSession(
      esysContext, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
      ESYS_TR_NONE, NULL, TPM2_SE_HMAC, &symmetric, TPM2_ALG_SHA256, &session);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Start session failed -> %s \n", Tss2_RC_Decode(rc));
    exit(1);
  }

  rc = Esys_TRSess_SetAttributes(esysContext, session,
                                 TPMA_SESSION_DECRYPT | TPMA_SESSION_ENCRYPT |
                                     TPMA_SESSION_CONTINUESESSION,
                                 0xff);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Set session attributes -> %s\n", Tss2_RC_Decode(rc));
    exit(1);
  }

  // Get the NV Index handle
  ESYS_TR nvHandle = ESYS_TR_NONE;
  rc = Esys_TR_FromTPMPublic(esysContext, NV_INDEX, ESYS_TR_NONE, ESYS_TR_NONE,
                             ESYS_TR_NONE, &nvHandle);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: Read TPM Public -> %s\n", Tss2_RC_Decode(rc));
    exit(1);
  }

  TPM2B_MAX_NV_BUFFER *seed = NULL;
  rc = Esys_NV_Read(esysContext, nvHandle, nvHandle, session, ESYS_TR_NONE,
                    ESYS_TR_NONE, 32, 0, &seed);
  if (rc != TSS2_RC_SUCCESS) {
    printf("\nError: NV Read -> %s\n", Tss2_RC_Decode(rc));
    exit(1);
  }

  Esys_FlushContext(esysContext, session);

  return seed->buffer;
}