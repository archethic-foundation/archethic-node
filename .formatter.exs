# Used by "mix format"
[
  plugins: [Phoenix.LiveView.HTMLFormatter, DoctestFormatter],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}",
    "apps/*/{lib,config,test}/**/*.{ex,exs}",
    "apps/*/mix.exs"
  ],
  import_deps: [:distillery]
]
