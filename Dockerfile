FROM hexpm/elixir:1.14.1-erlang-24.3.4.6-alpine-3.16.2 AS archethic-ci

ARG skip_tests=0
ARG MIX_ENV=prod

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

# running TESTNET with release upgrade should ???

RUN apk add --no-cache --update \
  build-base bash gcc git npm python3 wget openssl libsodium-dev gmp-dev

# Install hex and rebar
RUN mix local.rebar --force \
  && mix local.hex --if-missing --force

WORKDIR /opt/code

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config ./config
RUN mix do deps.get, deps.compile

# build assets
COPY priv ./priv
COPY assets ./assets 
RUN npm --prefix ./assets ci --progress=false --no-audit --loglevel=error 

COPY . .

RUN git config user.name aebot \
  && git config user.email aebot@archethic.net \
  && git remote add origin https://github.com/archethic-foundation/archethic-node

# Install Dart Sass
RUN npm install -g sass

# build Sass -> CSS
RUN cd assets && \
 sass --no-source-map --style=compressed css/app.scss ../priv/static/css/app.css && cd -

# build release
RUN mix do assets.deploy, distillery.release

# gen PLT
RUN if [ $with_tests -eq 1 ]; then mix git_hooks.run pre_push ;fi

# Install
RUN mkdir -p /opt/app \
  && cd /opt/app \
  && tar zxf /opt/code/_build/${MIX_ENV}/rel/archethic_node/releases/*/archethic_node.tar.gz
CMD /opt/app/bin/archethic_node foreground

################################################################################

FROM archethic-ci as build

FROM hexpm/elixir:1.14.1-erlang-24.3.4.6-alpine-3.16.2

RUN apk add --no-cache --update bash git openssl libsodium

COPY --from=build /opt/app /opt/app
COPY --from=build /opt/code/.git /opt/code/.git

WORKDIR /opt/code
RUN git reset --hard

WORKDIR /opt/app
CMD /opt/app/bin/archethic_node foreground
