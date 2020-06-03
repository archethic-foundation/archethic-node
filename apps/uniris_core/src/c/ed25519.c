#include <err.h>
#include <sodium.h>

#include "stdio_helpers.h"

enum { GENERATE_ED25519 = 1, GENERATE_ED25519_SEED = 2, ENCRYPT = 3, DECRYPT = 4, SIGN = 5, VERIFY = 6 };

void write_error(unsigned char* buf, char* error_message, int error_message_len);
void generate_ed25519(unsigned char* buf);
void generate_seed(unsigned char* buf, int pos, int len);
void encrypt(unsigned char* buf, int pos, int len);
void decrypt(unsigned char* buf, int pos, int len);
void sign(unsigned char* buf, int pos, int len);
void verify(unsigned char* buf, int pos, int len);

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
            case GENERATE_ED25519:
                generate_ed25519(buf);
                break;
            case GENERATE_ED25519_SEED:
                generate_seed(buf, pos, len);
                break;
            case ENCRYPT:
                encrypt(buf, pos, len);
                break;
            case DECRYPT:
                decrypt(buf, pos, len);
                break;
            case SIGN:
                sign(buf, pos, len);
                break;
            case VERIFY:
                verify(buf, pos, len);
                break;
        }

        free(buf);
        len = get_length();
    }
}

void generate_ed25519(unsigned char* buf) {
    unsigned char sk[crypto_sign_SECRETKEYBYTES];
    unsigned char pk[crypto_sign_PUBLICKEYBYTES];
    crypto_sign_keypair(pk, sk);

    unsigned char response[5+crypto_sign_SECRETKEYBYTES+crypto_sign_PUBLICKEYBYTES];
    for (int i = 0; i < 4; i++) {
        response[i] = buf[i];
    }

    //Encode response success type
    response[4] = 1;

    for (int i = 0; i < crypto_sign_SECRETKEYBYTES; i++){
        response[5+i] = sk[i];
    }

    for (int i = 0; i < crypto_sign_PUBLICKEYBYTES; i++){
        response[5+crypto_sign_SECRETKEYBYTES+i] = pk[i];
    }


    write_response(response, sizeof(response));

    sodium_memzero(pk, sizeof pk);
    sodium_memzero(sk, sizeof sk);
}

void generate_seed(unsigned char* buf, int pos, int len) {
    if (len < pos+crypto_sign_SEEDBYTES) {
        write_error(buf, "missing seed", 12);
    } else {
        unsigned char seed[crypto_sign_SEEDBYTES];
        for (int i = 0; i < crypto_sign_SEEDBYTES; i++) {
            seed[i] = buf[pos+i];
        }
        pos += crypto_sign_SEEDBYTES;

        unsigned char sk[crypto_sign_SECRETKEYBYTES];
        unsigned char pk[crypto_sign_PUBLICKEYBYTES];
        crypto_sign_seed_keypair(pk, sk, seed);

        unsigned char response[5+crypto_sign_SECRETKEYBYTES+crypto_sign_PUBLICKEYBYTES];
        for (int i = 0; i < 4; i++) {
            response[i] = buf[i];
        }

        //Encode response success type
        response[4] = 1;

        for (int i = 0; i < crypto_sign_SECRETKEYBYTES; i++){
            response[5+i] = sk[i];
        }

        for (int i = 0; i < crypto_sign_PUBLICKEYBYTES; i++){
            response[5+crypto_sign_SECRETKEYBYTES+i] = pk[i];
        }


        write_response(response, sizeof(response));

        sodium_memzero(seed, sizeof seed);
        sodium_memzero(pk, sizeof pk);
        sodium_memzero(sk, sizeof sk);
    }
}

void encrypt(unsigned char* buf, int pos, int len) {
    if (len < pos + crypto_sign_PUBLICKEYBYTES) {
        write_error(buf, "missing public key", 18);
    } else {
        unsigned char pk[crypto_sign_PUBLICKEYBYTES];
        for (int i = 0; i < crypto_sign_PUBLICKEYBYTES; i++) {
            pk[i] = buf[pos+i];
        }

        pos += crypto_sign_PUBLICKEYBYTES;

        unsigned char x25519_pk[crypto_scalarmult_curve25519_BYTES];
        if (crypto_sign_ed25519_pk_to_curve25519(x25519_pk, pk) != 0) {
            sodium_memzero(pk, sizeof pk);
            write_error(buf, "ed25519 public key to curve25519 failed", 39);
        } else {
            if (len < pos + 4) {
                sodium_memzero(pk, sizeof pk);
                sodium_memzero(x25519_pk, sizeof x25519_pk);
                write_error(buf, "missing message size", 20);
            } else {
                int message_len = buf[pos+3] | buf[pos+2] << 8 | buf[pos+1] << 16 | buf[pos] << 24;
                pos+=4;

                if (len < pos + message_len) {
                    write_error(buf, "missing message", 15);
                    sodium_memzero(pk, sizeof pk);
                    sodium_memzero(x25519_pk, sizeof x25519_pk);
                } else {
                        unsigned char *message = (unsigned char *) malloc(message_len);
                        for (int i = 0; i < message_len; i++) {
                            message[i] = buf[pos+i];
                        }
                        pos += message_len;

                        int cipher_len = crypto_box_SEALBYTES + message_len;
                        unsigned char *ciphertext = (unsigned char *) malloc(cipher_len);
                        if (crypto_box_seal(ciphertext, message, message_len, x25519_pk) != 0) {
                            sodium_memzero(pk, sizeof pk);
                            sodium_memzero(x25519_pk, sizeof x25519_pk);
                            sodium_memzero(message, message_len);
                            sodium_memzero(ciphertext, cipher_len);
                            write_error(buf, "encryption failed", 17);
                        } else {
                            int response_len = 5+4+cipher_len;
                            unsigned char *response = (unsigned char *) malloc(response_len);
                            for (int i = 0; i < 4; i++) {
                                response[i] = buf[i];
                            }

                            //Encode response success type
                            response[4] = 1;

                            //encode ciphertext length
                            response[5] = (cipher_len >> 24) & 0xFF;
                            response[6] = (cipher_len >> 16) & 0xFF;
                            response[7] = (cipher_len >> 8) & 0xFF;
                            response[8] = cipher_len & 0xFF;

                            for (int i = 0; i < cipher_len; i++){
                                response[9+i] = ciphertext[i];
                            }

                            write_response(response, response_len);
                            sodium_memzero(ciphertext, sizeof ciphertext);
                            sodium_memzero(message, sizeof message);
                            sodium_memzero(pk, sizeof pk);
                            sodium_memzero(x25519_pk, sizeof x25519_pk);
                            sodium_memzero(response, response_len);
                        }
                    }
            }
        }
        
    }
}

void decrypt(unsigned char* buf, int pos, int len) {
    if (len < pos + crypto_sign_SECRETKEYBYTES) {
        write_error(buf, "missing secret key", 18);
    } else {
        unsigned char sk[crypto_sign_SECRETKEYBYTES];
        for (int i = 0; i < crypto_sign_SECRETKEYBYTES; i++) {
            sk[i] = buf[pos+i];
        }
        pos += crypto_sign_SECRETKEYBYTES;

        unsigned char x25519_sk[crypto_scalarmult_curve25519_BYTES];
        if (crypto_sign_ed25519_sk_to_curve25519(x25519_sk, sk) != 0) {
            sodium_memzero(sk, sizeof(sk));
            write_error(buf, "ed25519 private key to curve25519 failed", 40);
        } else {
            unsigned char pk[crypto_sign_PUBLICKEYBYTES];
            for (int i = 0; i < crypto_sign_PUBLICKEYBYTES; i++) {
                pk[i] = sk[32+i];
            }

            unsigned char x25519_pk[crypto_scalarmult_curve25519_BYTES];
            if (crypto_sign_ed25519_pk_to_curve25519(x25519_pk, pk) != 0) {
                sodium_memzero(sk, sizeof(sk));
                sodium_memzero(pk, sizeof(pk));
                write_error(buf, "ed25519 public key to curve25519 failed", 39);
            } else {
                if (len < pos + 4) {
                    sodium_memzero(sk, sizeof(sk));
                    sodium_memzero(pk, sizeof(pk));
                    write_error(buf, "missing cipher size", 19);
                } else {
                    int cipher_len = buf[pos+3] | buf[pos+2] << 8 | buf[pos+1] << 16 | buf[pos] << 24;
                    pos+=4;

                    if (len < pos + cipher_len) {
                        sodium_memzero(sk, sizeof(sk));
                        sodium_memzero(pk, sizeof(pk));
                        write_error(buf, "missing cipher", 14);
                    } else {
                        unsigned char *ciphertext = (unsigned char *) malloc(cipher_len);
                        
                        for (int i = 0; i < cipher_len; i++) {
                            ciphertext[i] = buf[pos+i];
                        }
                        pos += cipher_len;

                        int message_size = cipher_len - crypto_box_SEALBYTES;

                        unsigned char *decrypted = (unsigned char *) malloc(message_size);
                        if(crypto_box_seal_open(decrypted, ciphertext, cipher_len, x25519_pk, x25519_sk) != 0) {
                            sodium_memzero(sk, sizeof(sk));
                            sodium_memzero(pk, sizeof(pk));
                            sodium_memzero(ciphertext, cipher_len);
                            sodium_memzero(decrypted, message_size);
                            write_error(buf, "decryption failed", 17);
                        } else {
                            int response_len = 5+message_size;
                            unsigned char *response = (unsigned char *) malloc(response_len);

                            //Encode request id
                            for (int i = 0; i < 4; i++) {
                                response[i] = buf[i];
                            }

                            //Encode response success type
                            response[4] = 1;

                            //Encode decrypted message
                            for (int i = 0; i < message_size; i++){
                                response[5+i] = decrypted[i];
                            }
                            write_response(response, response_len);

                            sodium_memzero(sk, sizeof(sk));
                            sodium_memzero(pk, sizeof(pk));
                            sodium_memzero(ciphertext, cipher_len);
                            sodium_memzero(decrypted, message_size);
                            sodium_memzero(response, response_len);
                        }
                    }
                }
            }
        }
    }
}

void sign(unsigned char* buf, int pos, int len) {
    if (len < pos + crypto_sign_SECRETKEYBYTES) {
        write_error(buf, "missing secret key", 18);
    } else {

        unsigned char sk[crypto_sign_SECRETKEYBYTES];
        for (int i = 0; i < crypto_sign_SECRETKEYBYTES; i++) {
            sk[i] = buf[pos+i];
        }
        pos += crypto_sign_SECRETKEYBYTES;

        int message_len = buf[pos+3] | buf[pos+2] << 8 | buf[pos+1] << 16 | buf[pos] << 24;
        pos+=4;
        
        if (len < pos + message_len) {
            sodium_memzero(sk, sizeof(sk));
            write_error(buf, "missing message", 15);
        } else {
                unsigned char *message = (unsigned char *) malloc(message_len);
                for (int i = 0; i < message_len; i++) {
                    message[i] = buf[i+pos];
                }
                pos+= message_len;

                unsigned char sig[crypto_sign_BYTES];
                if (crypto_sign_detached(sig, NULL, message, message_len, sk) != 0) {
                    sodium_memzero(sk, sizeof(sk));
                    sodium_memzero(sk, message_len);
                    write_error(buf, "signing failed", 14);
                } else {
                    unsigned char response[5+crypto_sign_BYTES];

                    //Encode request id
                    for (int i = 0; i < 4; i++) {
                        response[i] = buf[i];
                    }


                    //Encode response success type
                    response[4] = 1;

                    //Encode signature
                    for (int i = 0; i < crypto_sign_BYTES; i++){
                        response[5+i] = sig[i];
                    }
                    write_response(response, sizeof(response));

                    sodium_memzero(sk, sizeof sk);
                    sodium_memzero(message, sizeof message);
                    sodium_memzero(sig, sizeof sig);
                }
            }
    }
}

void verify(unsigned char* buf, int pos, int len) {
    if (len < pos + crypto_sign_PUBLICKEYBYTES) {
        write_error(buf, "missing public key", 18);
    } else {
        unsigned char pk[crypto_sign_PUBLICKEYBYTES];
        for (int i = 0; i < crypto_sign_PUBLICKEYBYTES; i++) {
            pk[i] = buf[pos+i];
        }
        pos += crypto_sign_PUBLICKEYBYTES;

        if (len < pos+4) {
            sodium_memzero(pk, sizeof(pk));
            write_error(buf, "missing message size", 20);
        } else {
            int message_len = (int)buf[pos+3] | (int)buf[pos+2] << 8 | (int)buf[pos+1] << 16 | (int)buf[pos] << 24;
            pos+=4;

            if (len < pos + message_len) {
                sodium_memzero(pk, sizeof(pk));
                write_error(buf, "missing message", 15);
            } else {
                    unsigned char *message = (unsigned char *) malloc(message_len);
                    for (int i = 0; i < message_len; i++) {
                        message[i] = buf[pos+i];
                    }
                    pos += message_len;

                    if (len < pos + crypto_sign_BYTES) {
                        sodium_memzero(pk, sizeof(pk));
                        sodium_memzero(message, message_len);
                        write_error(buf, "missing signature", 17);
                    } else {
                        unsigned char sig[crypto_sign_BYTES];
                        for (int i = 0; i < crypto_sign_BYTES; i++) {
                            sig[i] = buf[pos+i];
                        }
                        pos += crypto_sign_BYTES;

                        if (crypto_sign_verify_detached(sig, message, message_len, pk) != 0) {
                            write_error(buf, "invalid signature", 17);
                        }
                        else {
                            unsigned char response[5];
                            //Encode request id
                            for (int i = 0; i < 4; i++) {
                                response[i] = buf[i];
                            }

                            //Encode response success type
                            response[4] = 1;

                            write_response(response, sizeof(response));
                        }
                        sodium_memzero(pk, sizeof pk);
                        sodium_memzero(message, sizeof message);
                        sodium_memzero(sig, sizeof sig);
                    }
                }
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