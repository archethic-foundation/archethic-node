CC = /usr/bin/gcc

all: priv/c_dist priv/c_dist/libsodium priv/c_dist/hypergeometric_distribution

priv/c_dist/libsodium:
	$(CC) src/c/crypto/*.c -o priv/c_dist/libsodium -I src/c/crypto -lsodium

priv/c_dist/hypergeometric_distribution:
	$(CC) src/c/hypergeometric_distribution.c -o priv/c_dist/hypergeometric_distribution -lgmp

priv/c_dist:
	mkdir -p priv/c_dist
