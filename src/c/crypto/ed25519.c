#include <err.h>
#include <sodium.h>

#include "stdio_helpers.h"

enum { CONVERT_PUBLIC_KEY_ED25519_TO_CURVE25519 = 1, CONVERT_SECRET_KEY_ED25519_TO_CURVE25519 = 2 };

void convert_public_key(unsigned char* buf, int pos, int len);
void convert_secret_key(unsigned char* buf,  int pos, int len);
void write_error(unsigned char* buf, char* error_message, int error_message_len);

int main() {

    if (sodium_init() == -1) {
        err(EXIT_FAILURE, "Libsodium cannot be loaded");
    }

    int len = get_length();

    while(len > 0 ) {

        unsigned char *buf = (unsigned char *) malloc(len);
        int read_bytes = read_message(buf, len);

        if (read_bytes != len) {
            free(buf);
            err(EXIT_FAILURE, "missing message");
        }

        if (len < 4) {
            free(buf);
            err(EXIT_FAILURE, "missing request id");
        }
        int pos = 4; //After the 32 bytes of the request id

        if (len < 5) {
            free(buf);
            err(EXIT_FAILURE, "missing fun id");
        }

        unsigned char fun_id = buf[pos];
        pos++;

        switch (fun_id) {
            case CONVERT_SECRET_KEY_ED25519_TO_CURVE25519:
                convert_secret_key(buf, pos, len);
                break;
            case CONVERT_PUBLIC_KEY_ED25519_TO_CURVE25519:
                convert_public_key(buf, pos, len);
                break;
            default:
                err(EXIT_FAILURE, "invalid fun id");
        }

        free(buf);
        len = get_length();
    }
}

void convert_public_key(unsigned char* buf, int pos, int len) {
    if (len < pos + crypto_sign_PUBLICKEYBYTES) {
        write_error(buf, "missing public key", 18);
    } else {
        
        unsigned char ed25519_pk[crypto_sign_PUBLICKEYBYTES];
        for (int i = 0; i < crypto_sign_PUBLICKEYBYTES; i++) {
            ed25519_pk[i] = buf[pos+i];
        }

        pos += crypto_sign_PUBLICKEYBYTES;

        unsigned char x25519_pk[crypto_scalarmult_curve25519_BYTES];
        if (crypto_sign_ed25519_pk_to_curve25519(x25519_pk, ed25519_pk) != 0) {
            sodium_memzero(ed25519_pk, sizeof ed25519_pk);
            write_error(buf, "ed25519 public key to curve25519 failed", 39);
        } else {

            int response_len = 5 + crypto_scalarmult_curve25519_BYTES;
            unsigned char response[response_len];

            //Encode request id
            for (int i = 0; i < 4; i++) {
                response[i] = buf[i];
            }

            //Encode response success type
            response[4] = 1;

            for (int i = 0; i < crypto_scalarmult_curve25519_BYTES; i++){
                response[5+i] = x25519_pk[i];
            }

            write_response(response, response_len);
            sodium_memzero(ed25519_pk, sizeof ed25519_pk);
            sodium_memzero(x25519_pk, sizeof x25519_pk);
            sodium_memzero(response, response_len);
        }
    }
}

void convert_secret_key(unsigned char* buf, int pos, int len) {
    if (len < pos + crypto_sign_SECRETKEYBYTES) {
        write_error(buf, "missing secret key", 18);
    } else {
        unsigned char ed25519_sk[crypto_sign_SECRETKEYBYTES];
        for (int i = 0; i < crypto_sign_SECRETKEYBYTES; i++) {
            ed25519_sk[i] = buf[pos+i];
        }

        pos += crypto_sign_SECRETKEYBYTES;

        unsigned char x25519_sk[crypto_scalarmult_curve25519_BYTES];
        if (crypto_sign_ed25519_sk_to_curve25519(x25519_sk, ed25519_sk) != 0) {
            sodium_memzero(ed25519_sk, sizeof ed25519_sk);
            write_error(buf, "ed25519 secret key to curve25519 failed", 39);
        } else {
            int response_len = 5 + crypto_scalarmult_curve25519_BYTES;
            unsigned char response[response_len];

            //Encode request id
            for (int i = 0; i < 4; i++) {
                response[i] = buf[i];
            }

            //Encode response success type
            response[4] = 1;

            for (int i = 0; i < crypto_scalarmult_curve25519_BYTES; i++){
                response[5+i] = x25519_sk[i];
            }

            write_response(response, response_len);
            sodium_memzero(ed25519_sk, sizeof ed25519_sk);
            sodium_memzero(x25519_sk, sizeof x25519_sk);
            sodium_memzero(response, response_len);
        }
    }
}

void write_error(unsigned char* buf, char* error_message, int error_message_len) {
    int response_size = 5+error_message_len;
    unsigned char response[response_size];

    //Encode the request id
    for (int i = 0; i < 4; i++) {
        response[i] = buf[i];
    }

    // Error response type
    response[4] = 0;

    //Encode the error message
    for (int i = 0; i < error_message_len;i++) {
        response[5+i] = error_message[i];
    }
    write_response(response, response_size);
}
