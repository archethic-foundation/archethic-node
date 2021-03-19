#!/bin/bash

set -e

if [ ! -d $HOME/.mix ]; then
  mix local.hex --force
  mix local.rebar --force
fi

mix deps.get

should_compile=0

app="priv/static/js/app.js"
css="priv/static/css/app.css"

app_in=(assets/js/*.js)
css_in=(assets/css/*.scss)

declare -A src

src[$app]=app_in[@]
src[$css]=css_in[@]

for dst in "${!src[@]}"; do
  for f in "${!src[$dst]}"; do
    if [ "$f" -nt "$dst" ]; then
      should_compile=1
      break
    fi
  done
done

if [ $should_compile -eq 1 ]; then
  pushd assets
  npm ci --progress=false --no-audit --loglevel=error
  npm run deploy
  popd
fi

exec "$@"
