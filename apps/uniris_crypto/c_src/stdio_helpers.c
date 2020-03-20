#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <err.h>

int _read_exact(unsigned char *buf, int len) {
    int i, got=0;

    do {
        if ((i = read(0, buf+got, len-got)) <= 0)
        return(i);
        got += i;
    } 
    while (got<len);

    return(len);
}

int _write_exact(unsigned char *buf, int len)
{
  int i, wrote = 0;

  do {
    if ((i = write(1, buf+wrote, len-wrote)) <= 0) {
      return (i);
    }
    wrote += i;
  } 
  while (wrote<len);

  return (len);
}

int get_length() {
  unsigned char size_header[4];
  if (_read_exact(size_header, 4) != 4) {
    return 0;
  }

  int len = size_header[3] | size_header[2] << 8 | size_header[1] << 16 | size_header[0] << 24;
  return  len;
}

int read_message(unsigned char *buf, int len)
{
  int got = _read_exact(buf, len);
  return got;
}



int write_response(unsigned char *buf, int len)
{
  unsigned char size_header[4];

  size_header[0] = (len >> 24) & 0xFF;
  size_header[1] = (len >> 16) & 0xFF;
  size_header[2] = (len >> 8) & 0xFF;
  size_header[3] = len & 0xFF;

  _write_exact(size_header, 4);

  return _write_exact(buf, len);
}
