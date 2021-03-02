CC = /usr/bin/gcc

all: c_dist crypto hypergeometric_distribution

crypto:
	$(CC) src/c/crypto/*.c -o priv/c_dist/libsodium -I src/c/crypto/*.h -lsodium 

hypergeometric_distribution:
	$(CC) src/c/hypergeometric_distribution.c -o priv/c_dist/hypergeometric_distribution -lgmp

c_dist:
	mkdir -p priv/c_dist