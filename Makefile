CC = /usr/bin/gcc

all: c_dist crypto

crypto:
	$(CC) src/c/*.c -o priv/crypto/c_dist/libsodium -I src/c/*.h -lsodium 

c_dist:
	mkdir -p priv/crypto/c_dist
	