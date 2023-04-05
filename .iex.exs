IEx.configure(inspect: [limit: :infinity])

alias Archethic.Crypto
alias Archethic.DB
alias Archethic.P2P
alias Archethic.P2P.Node
alias Archethic.SharedSecrets
alias Archethic.Account
alias Archethic.Election
alias Archethic.Governance
alias Archethic.Contracts
alias Archethic.TransactionChain
alias Archethic.TransactionChain.Transaction
alias Archethic.TransactionChain.TransactionData
alias Archethic.BeaconChain


alias Archethic.Governance.Code.CICD.Docker
prop = %Archethic.Governance.Code.Proposal{
  address: <<0, 0, 135, 189, 175, 8, 43, 160, 49, 21, 23, 241, 61, 189, 221,
    177, 45, 120, 59, 243, 80, 75, 193, 250, 119, 188, 219, 73, 209, 197, 118,
    170, 122, 142>>,
  previous_public_key: <<0, 1, 62, 205, 23, 142, 29, 217, 94, 202, 136, 109,
    165, 135, 153, 205, 202, 132, 122, 116, 97, 18, 90, 34, 141, 225, 172, 138,
    16, 138, 85, 15, 41, 149>>,
  timestamp: nil,
  description: "\Testing code proposal\"",
  changes: "diff --git a/mix.exs b/mix.exs\nindex a82c0b3c..b94d4323 100644\n--- a/mix.exs\n+++ b/mix.exs\n@@ -4,7 +4,7 @@ defmodule Archethic.MixProject do\n   def project do\n     [\n       app: :archethic,\n-      version: \"1.0.7\",\n+      version: \"1.0.8\",\n       build_path: \"_build\",\n       config_path: \"config/config.exs\",\n       deps_path: \"deps\",\ndiff --git a/rel/appups/archethic/1.0.7_to_1.0.8.appup b/rel/appups/archethic/1.0.7_to_1.0.8.appup\nnew file mode 100644\nindex 00000000..18b6d541\n--- /dev/null\n+++ b/rel/appups/archethic/1.0.7_to_1.0.8.appup\n@@ -0,0 +1,4 @@\n+{\"1.0.8\",\n+ [{\"1.0.7\",\n+   [{load_module,'Elixir.Archethic', []}]}],\n+ [{\"1.0.7\",\n+   [{load_module,'Elixir.Archethic', []}]}]\n+}.\n",
  version: "1.0.8",
  files: ["mix.exs", "rel/appups/archethic/1.0.7_to_1.0.8.appup"],
  approvals: [
    <<0, 0, 135, 189, 175, 8, 43, 160, 49, 21, 23, 241, 61, 189, 221, 177, 45,
      120, 59, 243, 80, 75, 193, 250, 119, 188, 219, 73, 209, 197, 118, 170,
      122, 142>>,
    <<0, 0, 168, 220, 209, 92, 167, 255, 187, 168, 176, 63, 128, 210, 199, 35,
      63, 0, 252, 36, 147, 196, 130, 249, 233, 17, 132, 0, 6, 88, 232, 198, 98,
      44>>
  ]
}
