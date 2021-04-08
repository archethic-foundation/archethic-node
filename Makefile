CC = /usr/bin/gcc

all: priv/c_dist priv/c_dist/libsodium priv/c_dist/hypergeometric_distribution

priv/c_dist/libsodium:
	$(CC) src/c/crypto/*.c -o priv/c_dist/libsodium -I src/c/crypto -lsodium

priv/c_dist/hypergeometric_distribution:
	$(CC) src/c/hypergeometric_distribution.c -o priv/c_dist/hypergeometric_distribution -lgmp

priv/c_dist:
	mkdir -p priv/c_dist

clean:
	rm -f priv/c_dist/libsodium
	rm -f priv/c_dist/hypergeometric_distribution

hostclean: clean
	-docker container stop $$(docker ps -a --filter=name=utn* -q)
	-docker container rm   $$(docker ps -a --filter=name=utn* -q)
	-docker container rm uniris-prop-313233
	-docker network rm $$(docker network ls --filter=name=utn-* -q)
	-docker image rm uniris-ci uniris-cd uniris-dev
	-rm -rf /tmp/utn-*
