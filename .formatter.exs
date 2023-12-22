# Used by "mix format"
[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}",
    "apps/*/{lib,config,test}/**/*.{ex,exs}",
    "apps/*/mix.exs"
  ],
  import_deps: [:distillery]
]
