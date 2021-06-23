CC = /usr/bin/gcc
OS := $(shell uname)

all: compile_c_programs

compile_c_programs:
	mkdir -p priv/c_dist
	$(CC) src/c/crypto/stdio_helpers.c src/c/crypto/ed25519.c -o priv/c_dist/libsodium -I src/c/crypto/stdio_helpers.h -lsodium
	$(CC) src/c/hypergeometric_distribution.c -o priv/c_dist/

ifeq ($(OS),Linux)
  if ldconfig -p | grep libtss2-esys; then 
	  $(CC) src/c/crypto/stdio_helpers.c src/c/crypto/tpm/lib.c src/c/crypto/tpm/port.c -o priv/c_dist/tpm/port -I src/c/crypto/stdio_helpers.h src/c/crypto/tpm/lib.h -ltss2-esys
    $(CC) src/c/crypto/tpm/keygen.c  src/c/crypto/tpm/lib.c -o priv/c_dist/tpm/keygen -ltss2-esys -lcrypto
  fi
endif

clean:
	rm -f priv/c_dist/libsodium
	rm -f priv/c_dist/hypergeometric_distribution
	rm -rf data*
	mix archethic.clean_db

install_system_deps:
ifeq ($(OS),Linux)
	sh scripts/install/system_deps_install.sh
	sh scripts/install/openssl_install.sh
	sh scripts/install/erlang_elixir_install.sh
	sh scripts/install/libsodium_install.sh
	sh scripts/install/docker_install.sh
	sh scripts/install/scylldb_install.sh
	sh scripts/install/tpm_install.sh
endif

tpm_keygen:
	sh scripts/install/tpm_keygen.sh

install: install_system_deps
ifeq ($(OS),Linux)
	if ldconfig -p | grep libtss2-esys; then 
		sh scripts/install/tpm_keygen.sh
	fi
endif

release:
	sh scripts/release.sh

docker-clean: clean
	docker container stop $$(docker ps -a --filter=name=utn* -q)
	docker container rm   $$(docker ps -a --filter=name=utn* -q)
	docker container rm archethic-prop-313233
	docker network rm $$(docker network ls --filter=name=utn-* -q)
	docker image rm archethic-ci archethic-cd archethic-dev
	rm -rf /tmp/utn-*
