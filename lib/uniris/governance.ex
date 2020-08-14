# defmodule Uniris.Governance do
#   @moduledoc """
#   Handle the governance onchain by supporting testnet and mainnet updates using quorum of votes
#   for any protocol updates through code approvals and metrics approvals
#   """

#   alias Uniris.Storage

#   alias Uniris.Transaction
#   alias Uniris.TransactionData

#   require Logger

#   @doc """
#   Defines the acceptance threshold for a code approval quorum to go to the testnet evaluation
#   """
#   @spec code_approvals_threshold() :: float()
#   def code_approvals_threshold do
#     0.5
#   end

#   @doc """
#   Defines the acceptance threshold for a code metrics quorum to go to the mainnet
#   """
#   @spec metrics_approval_threshold() :: float()
#   def metrics_approval_threshold do
#     0.8
#   end

#   @spec run_continuous_integration(Transaction.t()) :: :ok | :error
#   def run_continuous_integration(tx = %Transaction{}) do
#     with :ok <- fork_code(tx),
#          {_, 0} <- System.cmd("mix", ["compile", "--warnings-as-errors"], stderr_to_stdout: true),
#          {_, 0} <- System.cmd("mix", ["test"], stderr_to_stdout: true) do
#       :ok
#     else
#       {_return, _exit_status} ->
#         {:error, :invalid_integration}
#     end
#   end

#   @spec deploy_testnet(binary()) :: :ok | {:error, :invalid_deployment}
#   def deploy_testnet(address) do
#     with {:ok, %Transaction{timestamp: timestamp}} <- Storage.get_transaction(address) do
#       #  :ok <- fork_code(tx) do
#       p2p_port = rem(DateTime.to_unix(timestamp), 11111)
#       web_port = rem(DateTime.to_unix(timestamp), 22222)

#       case System.cmd("iex", ["-S", "mix", "phx.server"],
#              env: [
#                {"MIX_ENV", "prod"},
#                {"UNIRIS_P2P_PORT", Integer.to_string(p2p_port)},
#                {"UNIRIS_WEB_PORT", Integer.to_string(web_port)}
#              ],
#              stderr_to_stdout: true
#            ) do
#         {_, 0} ->
#           :ok

#         {error, _} ->
#           IO.inspect(error)
#           {:error, :invalid_deployment}
#       end
#     else
#       {:error, :transaction_not_exists} = e ->
#         e

#       _ ->
#         {:error, :invalid_deployment}
#     end
#   end

#   defp fork_code(%Transaction{address: address, data: %TransactionData{content: content}}) do
#     patch_file = Path.join(File.cwd!(), "proposal_#{Base.encode16(address)}")
#     File.write!(patch_file, content)

#     {branches, _} = System.cmd("git", ["branch", "-l"])

#     branches =
#       branches
#       |> String.split("\n", trim: true)
#       |> Enum.map(&String.trim/1)

#     unless Base.encode16(address) in branches do
#       System.cmd("git", ["checkout", "-b", Base.encode16(address)])
#     end

#     case System.cmd("git", ["apply", patch_file], stderr_to_stdout: true) do
#       {_, 0} ->
#         System.cmd("git", ["commit", "-m", commit_message(content)])
#         File.rm!(patch_file)
#         :ok

#       {_errors, _} ->
#         File.rm!(patch_file)
#         {:error, :invalid_code_patch}
#     end
#   end

#   defp commit_message(content) do
#     [description_match] = Regex.scan(~r/(?<=Description:).+?(?=Changes:)/s, content)

#     description_match
#     |> List.first()
#     |> String.trim()
#   end
# end
