CC = /usr/bin/gcc

all: c_dist crypto

crypto:
	$(CC) priv/crypto/c_src/*.c -o priv/crypto/c_dist/libsodium -I priv/crypto/c_src/*.h -lsodium 

c_dist:
	mkdir -p priv/crypto/c_dist
	