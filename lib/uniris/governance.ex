defmodule Uniris.Governance do
  @moduledoc """
  Handle the governance onchain by supporting testnet and mainnet updates using quorum of votes
  for any protocol updates through code approvals and metrics approvals
  """

  alias __MODULE__.Git
  alias __MODULE__.ProposalMetadata
  alias __MODULE__.Testnet

  alias Uniris.Storage

  alias Uniris.Transaction
  alias Uniris.TransactionData

  require Logger

  @doc """
  Defines the acceptance threshold for a code approval quorum to go to the testnet evaluation
  """
  @spec code_approvals_threshold() :: float()
  def code_approvals_threshold do
    0.5
  end

  @doc """
  Defines the acceptance threshold for a code metrics quorum to go to the mainnet
  """
  @spec metrics_approval_threshold() :: float()
  def metrics_approval_threshold do
    0.8
  end

  @doc """
  Performs some verifications for the proposal (i.e version upgrade)
  """
  @spec preliminary_checks(Transaction.t()) ::
          :ok
          | {:error, :missing_version}
          | {:error, :invalid_version}
          | {:error, :invalid_changes}
  def preliminary_checks(
        tx = %Transaction{
          type: :code_proposal,
          data: %TransactionData{content: content}
        }
      ) do
    changes = ProposalMetadata.get_changes(content)

    with {:ok, ver} <- ProposalMetadata.get_version(changes),
         :gt <- Version.compare(ver, current_version()),
         :ok <- Git.fork_proposal(tx) do
      :ok
    else
      false ->
        {:error, :invalid_version}

      {:error, _} = e ->
        e
    end
  end

  defp current_version do
    {:ok, vsn} = :application.get_key(:uniris, :vsn)
    List.to_string(vsn)
  end

  @doc """
  Deploy the testnet for the given proposal address
  """
  @spec deploy_testnet(binary()) :: :ok | {:error, :invalid_changes}
  def deploy_testnet(address) do
    {:ok, tx} = Storage.get_transaction(address)
    Testnet.deploy(tx)
  end
end
