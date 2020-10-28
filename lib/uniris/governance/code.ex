defmodule Uniris.Governance.Code do
  @moduledoc """
  Provide functions to handle the code management and deployment
  """

  alias Uniris.Crypto

  alias __MODULE__.CI
  alias __MODULE__.Proposal
  alias __MODULE__.TestNet

  alias Uniris.Governance.Pools

  alias Uniris.P2P

  alias Uniris.Replication

  alias Uniris.TransactionChain

  alias Uniris.Utils

  @src_dir Application.compile_env(:uniris, :src_dir)

  @doc """
  List the source files from the master branch
  """
  @spec list_source_files() :: list(binary())
  def list_source_files do
    {files, 0} = System.cmd("git", ["ls-tree", "-r", "master", "--name-only"], cd: @src_dir)
    String.split(files, "\n", trim: true)
  end

  @doc """
  Determine if the code proposal can be deployed into testnet
  """
  @spec testnet_deployment?(binary()) :: boolean()
  def testnet_deployment?(proposal_address) when is_binary(proposal_address) do
    storage_nodes =
      Replication.chain_storage_nodes(proposal_address, P2P.list_nodes(availability: :global))

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      approvals = TransactionChain.list_signatures_for_pending_transaction(proposal_address)
      ratio = length(approvals) / length(Pools.members_of(:technical_council))
      ratio >= Pools.threshold_acceptance_for(:technical_council)
    else
      false
    end
  end

  @doc """
  Deploy the proposal into a dedicated testnet
  """
  @spec deploy_proposal_testnet(Proposal.t()) :: :ok
  defdelegate deploy_proposal_testnet(prop), to: TestNet, as: :deploy_proposal

  @doc """
  Ensure the code proposal is valid according to the defined rules:
  - Version in the code proposal must be greater than the current running version.
  - Git diff/patch must be valid. A fork is make to apply the diff and run the CI tasks
  """
  @spec valid_proposal?(Proposal.t()) :: boolean()
  def valid_proposal?(prop = %Proposal{version: version}) do
    with :gt <- Version.compare(version, current_version()),
         :ok <- CI.run(prop) do
      true
    else
      _ ->
        false
    end
  end

  defp current_version do
    {:ok, vsn} = :application.get_key(:uniris, :vsn)
    List.to_string(vsn)
  end

  @spec list_proposal_CI_logs(binary()) :: Enumerable.t()
  defdelegate list_proposal_CI_logs(address),
    to: CI,
    as: :list_logs
end
