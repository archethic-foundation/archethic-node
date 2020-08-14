FROM bitwalker/alpine-elixir:latest

RUN apk add --no-cache --update openssl wget build-base git npm python3

RUN wget https://download.libsodium.org/libsodium/releases/LATEST.tar.gz && \
    mkdir /opt/libsodium && tar zxvf LATEST.tar.gz -C /opt/libsodium && \
    cd /opt/libsodium/libsodium-stable && ./configure && \
    make && make install

WORKDIR /opt/app

COPY . .

# Will install the application at /opt/build
RUN ./release.sh

CMD ["/bin/bash"]