CC = /usr/bin/gcc
OS := $(shell uname)

all: compile_c_programs

compile_c_programs:
	mkdir -p priv/c_dist
	$(CC) src/c/crypto/stdio_helpers.c src/c/crypto/ed25519.c -o priv/c_dist/libsodium -I src/c/crypto/stdio_helpers.h -lsodium
	$(CC) src/c/hypergeometric_distribution.c -o priv/c_dist/hypergeometric_distribution -lgmp
	
#ifeq ($(OS),Linux)
#	# ldconfig -p | grep libtss2-esys
#	$(CC) src/c/crypto/stdio_helpers.c src/c/crypto/tpm.c src/c/crypto/tpm_port.c -o priv/c_dist/tpm -I src/c/crypto/stdio_helpers.h src/c/crypto/tpm.h -ltss2-esys
#endif

clean:
	rm -f priv/c_dist/libsodium
	rm -f priv/c_dist/hypergeometric_distribution
	rm -rf data*
	mix archethic.clean_db

install_system_deps:
	sh scripts/system_deps_install.sh
	sh scripts/openssl_install.sh
	sh scripts/erlang_elixir_install.sh
	sh scripts/libsodium_install.sh
	sh scripts/docker_install.sh
	sh scripts/scylldb_install.sh

install: install_system_deps release

release:
	sh scripts/release.sh

docker-clean: clean
	-docker container stop $$(docker ps -a --filter=name=utn* -q)
	-docker container rm   $$(docker ps -a --filter=name=utn* -q)
	-docker container rm archethic-prop-313233
	-docker network rm $$(docker network ls --filter=name=utn-* -q)
	-docker image rm archethic-ci archethic-cd archethic-dev
	-rm -rf /tmp/utn-*
