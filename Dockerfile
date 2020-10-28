FROM bitwalker/alpine-elixir:latest

# Install system requirements
RUN apk add --no-cache --update
    openssl \
    build-base \
    gcc \
    git \
    npm \
    python3 \
    wget

# Install Libsodium
RUN wget https://download.libsodium.org/libsodium/releases/LATEST.tar.gz && \
    mkdir /opt/libsodium && \
    tar zxvf LATEST.tar.gz -C /opt/libsodium && \
    cd /opt/libsodium/libsodium-stable && \
    ./configure && \
    make && \
    make install

WORKDIR /opt/app

ENV MIX_ENV prod

COPY . .

# Install dependencies
# Cache Elixir deps
RUN mix deps.get --only prod
RUN mix deps.compile

WORKDIR /opt/app/assets

# Cache Node deps
RUN npm install

# Compile JavaScript
RUN npm run deploy

WORKDIR /opt/app

# Prepare the image
RUN mix compile
RUN mix phx.digest