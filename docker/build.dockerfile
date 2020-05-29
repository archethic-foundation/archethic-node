FROM ubuntu

ENV VERSION=$version
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8

# Install Erlang,Elixir and build essentials
RUN apt-get update && \
  apt-get install -y wget gnupg2 build-essential -y locales git && \
  locale-gen en_US.UTF-8 && \
  wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && \
  dpkg -i erlang-solutions_2.0_all.deb && \
  apt-get update && \
  apt-get install -y esl-erlang elixir

# Install libsodium
RUN wget https://download.libsodium.org/libsodium/releases/LATEST.tar.gz && \
    tar zxvf LATEST.tar.gz && \
    cd libsodium-stable && \
    ./configure && \
    make && make check && \
    make install && \
    ldconfig

RUN mkdir /opt/build
WORKDIR /opt/build
COPY . .

CMD ["/bin/bash"]