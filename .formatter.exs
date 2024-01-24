# Used by "mix format"
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}",
    "apps/*/{lib,config,test}/**/*.{ex,exs}",
    "apps/*/mix.exs",
    "priv/migration_tasks/**/*.exs"
  ],
  import_deps: [:distillery]
]
