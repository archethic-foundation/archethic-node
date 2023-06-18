FROM elixir:1.14.1-alpine AS archethic-ci

ARG with_tests=1
ARG MIX_ENV=prod
ARG USER_ID
ARG GROUP_ID

# CI
#  - compile
#  - release
#  - gen PLT

# running CI with proposal should generate release upgrade
#  - commit proposal
#  - compile
#  - run ci
#  - generate release upgrade

######### TODO
# TESTNET
#  - code
#  - release

ENV ARCHETHIC_NETWORK_TYPE=testnet

RUN apk add --no-cache --update \
  build-base \
  grep \
  bash \
  gcc \
  make \
  g++ \
  git \
  npm \
  wget \
  openssl \
  libsodium-dev \
  libexecinfo-dev \
  gmp-dev

# Install hex and rebar
RUN mix local.rebar --force \
  && mix local.hex --if-missing --force

WORKDIR /opt/code

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config ./config
RUN mix do deps.get, deps.compile

COPY . .

# build assets
RUN npm --prefix ./assets ci --progress=false --no-audit --loglevel=error

RUN git config user.name aebot \
  && git config user.email aebot@archethic.net \
  && git remote add origin https://github.com/archethic-foundation/archethic-node

# build release
RUN mix assets.deploy
RUN MIX_ENV=${MIX_ENV} mix distillery.release
# Install
RUN mkdir -p /opt/app \
  && tar zxf /opt/code/_build/${MIX_ENV}/rel/archethic_node/releases/*/archethic_node.tar.gz -C  /opt/app
CMD /opt/app/bin/archethic_node foreground

################################################################################

FROM archethic-ci as build

FROM elixir:1.14.1-alpine

ARG USER_ID
ARG GROUP_ID

RUN apk add --no-cache --update bash git openssl libsodium libexecinfo

COPY --from=build /opt/app /opt/app
COPY --from=build /opt/code/.git /opt/code/.git

WORKDIR /opt/code
RUN git reset --hard

RUN rm -rf /opt/code/.git
RUN rm -rf /opt/code/priv

WORKDIR /opt/app
CMD /opt/app/bin/archethic_node foreground
