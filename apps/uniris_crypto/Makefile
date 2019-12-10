CC = /usr/bin/gcc

crypto:
	$(CC) c_src/*.c -o priv/c/crypto -I c_src/*.h -lsodium 

c_priv:
	mkdir -p priv/c

clean: 
	rm c_src/*.o

	