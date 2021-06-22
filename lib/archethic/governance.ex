defmodule ArchEthic.Governance do
  @moduledoc """
  Handle the governance on-chain by supporting testnet and mainNet updates using quorum of votes
  for any protocol updates through code approvals and metrics approvals
  """

  alias ArchEthic.Crypto

  alias __MODULE__.Code
  alias __MODULE__.Code.Proposal
  alias __MODULE__.Pools

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  @proposal_tx_select_fields [
    :address,
    :timestamp,
    :previous_public_key,
    data: [:content]
  ]

  @doc """
  List all the proposals regarding code changes
  """
  @spec list_code_proposals() :: Enumerable.t()
  def list_code_proposals do
    TransactionChain.list_transactions_by_type(:code_proposal, @proposal_tx_select_fields)
    |> Stream.map(fn tx ->
      {:ok, proposal} = Proposal.from_transaction(tx)

      Proposal.add_approvals(
        proposal,
        TransactionChain.list_signatures_for_pending_transaction(tx.address)
      )
    end)
  end

  @doc """
  Get a code proposal
  """
  @spec get_code_proposal(address :: binary()) :: {:ok, Proposal.t()} | {:error, :not_found}
  def get_code_proposal(address) when is_binary(address) do
    case TransactionChain.get_transaction(address, @proposal_tx_select_fields) do
      {:ok, tx} ->
        {:ok, prop} = Proposal.from_transaction(tx)
        signatures = TransactionChain.list_signatures_for_pending_transaction(address)
        prop = Proposal.add_approvals(prop, signatures)
        {:ok, prop}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  List all the source file from the master branch
  """
  @spec list_source_files() :: list(binary())
  defdelegate list_source_files, to: Code

  @doc """
  Show the content of a file from the last changes
  """
  @spec file_content(binary()) :: binary()
  defdelegate file_content(filename), to: Code

  @doc """
  Determine if the proposal changes are valid
  """
  @spec valid_code_changes?(Proposal.t()) :: boolean
  defdelegate valid_code_changes?(prop), to: Code, as: :valid_proposal?

  @doc """
  Determine if the public key is member of the given pool
  """
  @spec pool_member?(Crypto.key(), Pools.pool()) :: boolean()
  defdelegate pool_member?(public_key, pool), to: Pools, as: :member_of?

  @doc """
  List the member keys in the given pool
  """
  @spec pool_members(Pools.pool()) :: list(Crypto.key())
  defdelegate pool_members(pool), to: Pools, as: :members_of

  @doc """
  List the integration logs for the given code proposal address
  """
  @spec list_code_proposal_integration_logs(binary()) :: Enumerable.t()
  defdelegate list_code_proposal_integration_logs(address),
    to: Code,
    as: :list_proposal_CI_logs

  @doc """
  Load transaction into the Governance context triggering some behaviors:
  - Code proposals can trigger integration testing
  - Code approvals can trigger testnet deployment
  - Metric approvals can trigger MainNet deployment
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        type: :code_approval,
        data: %TransactionData{
          recipients: [prop_address]
        }
      }) do
    if Code.testnet_deployment?(prop_address) do
      {:ok, prop} = get_code_proposal(prop_address)
      Code.deploy_proposal_testnet(prop)
    else
      :ok
    end
  end

  def load_transaction(_), do: :ok
end
