#include "../stdio_helpers.h"
#include "lib.h"
#include <err.h>
#include <stdio.h>
#include <stdlib.h>

void write_error(unsigned char *buf, char *error_message,
                 int error_message_len);

enum {
  INITIALIZE = 1,
  GET_PUBLIC_KEY = 2,
  SIGN_ECDSA = 3,
  RETRIEVE_NODE_SEED = 4
};

void initialize_tpm(unsigned char *buf, int pos, int len) {
  if (len < pos + 2) {
    write_error(buf, "missing index", 13);
  } else {
    BYTE index[2];
    for (int i = 0; i < 2; i++) {
      index[i] = buf[pos + i];
    }

    INT index_int = index[1] | index[0] << 8;
    initializeTPM(index_int);

    int response_len = 5;
    unsigned char response[response_len];

    // Encoding of the request id
    for (int i = 0; i < 4; i++) {
      response[i] = buf[i];
    }

    // Encoding of success
    response[4] = 1;
    write_response(response, response_len);
  }
}

void get_public_key(unsigned char *buf, int pos, int len) {
  if (len < pos + 2) {
    write_error(buf, "missing index", 13);
  } else {
    BYTE index[2];
    for (int i = 0; i < 2; i++) {
      index[i] = buf[pos + i];
    }

    INT index_int = index[1] | index[0] << 8;

    BYTE *asnkey;
    INT publicKeySize = 0;
    asnkey = getPublicKey(index_int, &publicKeySize);
    int response_len = 5 + publicKeySize;

    unsigned char response[response_len];
    // Encode request's ID
    for (int i = 0; i < 4; i++) {
      response[i] = buf[i];
    }

    // Encoding of success
    response[4] = 1;

    for (int i = 0; i < publicKeySize; i++) {
      response[5 + i] = asnkey[i];
    }

    write_response(response, response_len);
  }
}

void sign_ecdsa(unsigned char *buf, int pos, int len) {
  BYTE hash256[32];

  if (len < pos + 2) {
    write_error(buf, "missing index", 13);
  } else {
    BYTE index[2];
    for (int i = 0; i < 2; i++) {
      index[i] = buf[pos + i];
    }

    pos += 2;

    for (int i = 0; i < 32; i++) {
      hash256[i] = buf[pos + i];
    }

    INT index_int = index[1] | index[0] << 8;

    BYTE *eccSign;
    INT signLen = 0;

    eccSign = signECDSA(index_int, hash256, &signLen, false);

    int response_len = 5 + signLen;
    unsigned char response[response_len];
    for (int i = 0; i < 4; i++) {
      response[i] = buf[i];
    }

    // Encoding of success
    response[4] = 1;

    for (int i = 0; i < signLen; i++) {
      response[5 + i] = eccSign[i];
    }

    write_response(response, response_len);
  }
}

void getNodeSeed(unsigned char *buf, int pos, int len) {
  BYTE *seed;
  seed = retrieveNodeSeed();

  int response_len = 5 + 32; // seed => 32 bytes;

  unsigned char response[response_len];
  // Encode request's ID
  for (int i = 0; i < 4; i++) {
    response[i] = buf[i];
  }

  // Encoding of success
  response[4] = 1;

  for (int i = 0; i < 32; i++) {
    response[5 + i] = seed[i];
  }

  write_response(response, response_len);
}

int main() {
  int len = get_length();

  while (len > 0) {

    unsigned char *buf = (unsigned char *)malloc(len);
    int read_bytes = read_message(buf, len);

    if (read_bytes != len) {
      free(buf);
      err(EXIT_FAILURE, "missing message");
    }

    if (len < 4) {
      free(buf);
      err(EXIT_FAILURE, "missing request id");
    }
    int pos = 4; // After the 32 bytes of the request id

    if (len < 5) {
      free(buf);
      err(EXIT_FAILURE, "missing fun id");
    }

    unsigned char fun_id = buf[pos];
    pos++;

    switch (fun_id) {

    case INITIALIZE:
      initialize_tpm(buf, pos, len);
      break;
    case GET_PUBLIC_KEY:
      get_public_key(buf, pos, len);
      break;
    case SIGN_ECDSA:
      sign_ecdsa(buf, pos, len);
      break;
    case RETRIEVE_NODE_SEED:
      getNodeSeed(buf, pos, len);
      break;
    }

    free(buf);
    len = get_length();
  }
}

void write_error(unsigned char *buf, char *error_message,
                 int error_message_len) {
  int response_size = 5 + error_message_len;
  unsigned char response[response_size];

  // Encode the request id
  for (int i = 0; i < 4; i++) {
    response[i] = buf[i];
  }

  // Error response type
  response[4] = 0;

  // Encode the error message
  for (int i = 0; i < error_message_len; i++) {
    response[5 + i] = error_message[i];
  }
  write_response(response, response_size);
}
