OS = $(shell uname -s)
CC = /usr/bin/gcc

ifeq ($(OS),Darwin)
	CC = /usr/local/opt/llvm/bin/clang -I/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include
endif

all: c_priv hypergeometric_distribution

hypergeometric_distribution: 
	$(CC) c_src/*.c -fopenmp -o priv/c/hypergeometric_distribution -lgmp

c_priv:
	mkdir -p priv/c

clean: 
	rm c_src/*.o