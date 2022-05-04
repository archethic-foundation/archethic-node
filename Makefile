CC = /usr/bin/gcc
OS := $(shell uname)
TPM_INSTALLED := $(shell ldconfig -p | grep libtss2-esys.so > /dev/null; echo $$?)

all: compile_c_programs

compile_c_programs:
	mkdir -p priv/c_dist
	$(CC) src/c/crypto/stdio_helpers.c src/c/crypto/ed25519.c -o priv/c_dist/libsodium_port -I src/c/crypto/stdio_helpers.h -lsodium
	$(CC) src/c/hypergeometric_distribution.c -o priv/c_dist/hypergeometric_distribution -lgmp

ifeq ($(TPM_INSTALLED),0)
	$(CC) src/c/crypto/stdio_helpers.c src/c/crypto/tpm/lib.c src/c/crypto/tpm/port.c -o priv/c_dist/tpm_port -I src/c/crypto/stdio_helpers.h -I src/c/crypto/tpm/lib.h -ltss2-esys
	$(CC) src/c/crypto/tpm/keygen.c src/c/crypto/tpm/lib.c -o priv/c_dist/tpm_keygen -I src/c/crypto/tpm/lib.h -ltss2-esys -lcrypto
endif


clean:
	rm -f priv/c_dist/*
	mix archethic.clean_db

docker-clean: clean
	docker container stop $$(docker ps -a --filter=name=utn* -q)
	docker container rm   $$(docker ps -a --filter=name=utn* -q)
	docker container rm archethic-prop-313233
	docker network rm $$(docker network ls --filter=name=utn-* -q)
	docker image rm archethic-ci archethic-cd archethic-dev
	rm -rf /tmp/utn-*
