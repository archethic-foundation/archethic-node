#include <stdio.h>
#include <openssl/sha.h>
#include "lib.h"

void main()
{
    initializeTPM(1);

    INT publicKeySize = 0;
    BYTE *asnkey;

    for (int z = 0; z < 500; z++)
    {
        asnkey = getPublicKey(z, &publicKeySize);
        for (int v = 26; v < publicKeySize; v++)
        {
            printf("%02x", asnkey[v]);
        }
        printf("\n");
    }
}

