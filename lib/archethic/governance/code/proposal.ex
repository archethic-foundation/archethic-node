defmodule Archethic.Governance.Code.Proposal do
  @moduledoc """
  Represents a proposal for code changes
  """

  alias __MODULE__.Parser

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  defstruct [
    :address,
    :previous_public_key,
    :timestamp,
    :description,
    :changes,
    :version,
    :files,
    approvals: []
  ]

  @type t :: %__MODULE__{
          address: binary(),
          previous_public_key: Crypto.key(),
          timestamp: nil | DateTime.t(),
          description: binary(),
          changes: binary(),
          version: binary(),
          files: list(binary()),
          approvals: list(binary())
        }

  @doc """
  Create a code proposal from a transaction
  """
  @spec from_transaction(Transaction.t()) ::
          {:ok, t()}
          | {:error, :missing_description}
          | {:error, :missing_changes}
          | {:error, :missing_version}
  def from_transaction(%Transaction{
        address: address,
        data: %TransactionData{content: content},
        previous_public_key: previous_public_key
      }) do
    with {:ok, description} <- Parser.get_description(content),
         {:ok, changes} <- Parser.get_changes(content),
         {:ok, version} <- Parser.get_version(changes) do
      {:ok,
       %__MODULE__{
         address: address,
         previous_public_key: previous_public_key,
         description: description,
         changes: changes,
         version: version,
         files: Parser.list_files(changes),
         approvals: []
       }}
    end
  end

  def from_transaction(
        tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}}
      ) do
    case from_transaction(tx) do
      {:ok, prop} ->
        {:ok, %{prop | timestamp: timestamp}}

      {:error, _} = e ->
        e
    end
  end

  @doc """
  Add the approvals to the code proposal

  ## Examples

      iex> %Proposal{}
      ...> |> Proposal.add_approvals([
      ...>   <<0, 145, 11, 248, 77, 93, 69, 102, 3, 217, 40, 238, 90, 2, 240, 137, 127, 242, 124,
      ...>     105, 141, 192, 142, 148, 132, 159, 146, 51, 214, 138, 64, 184, 230>>
      ...> ])
      %Proposal{
        approvals: [
          <<0, 145, 11, 248, 77, 93, 69, 102, 3, 217, 40, 238, 90, 2, 240, 137, 127, 242, 124, 105,
            141, 192, 142, 148, 132, 159, 146, 51, 214, 138, 64, 184, 230>>
        ]
      }
  """
  @spec add_approvals(t(), list(binary())) :: t()
  def add_approvals(prop = %__MODULE__{}, approvals) do
    %{prop | approvals: approvals}
  end

  @doc """
  Add an approval to the code proposal

  ## Examples

      iex> %Proposal{}
      ...> |> Proposal.add_approval(
      ...>   <<0, 145, 11, 248, 77, 93, 69, 102, 3, 217, 40, 238, 90, 2, 240, 137, 127, 242, 124,
      ...>     105, 141, 192, 142, 148, 132, 159, 146, 51, 214, 138, 64, 184, 230>>
      ...> )
      %Proposal{
        approvals: [
          <<0, 145, 11, 248, 77, 93, 69, 102, 3, 217, 40, 238, 90, 2, 240, 137, 127, 242, 124, 105,
            141, 192, 142, 148, 132, 159, 146, 51, 214, 138, 64, 184, 230>>
        ]
      }
  """
  @spec add_approval(t(), binary()) :: t()
  def add_approval(prop = %__MODULE__{}, address) when is_binary(address) do
    Map.update(prop, :approvals, [address], &[address | &1])
  end

  @doc """
  Determine code proposal TestNets ports

  ## Examples

      iex> %Proposal{timestamp: ~U[2020-08-17 08:10:16.338088Z]} |> Proposal.testnet_ports()
      {11296, 16885}
  """
  @spec testnet_ports(t()) ::
          {p2p_port :: :inet.port_number(), web_port :: :inet.port_number()}
  def testnet_ports(%__MODULE__{timestamp: timestamp}) do
    {
      rem(DateTime.to_unix(timestamp), 12_345),
      rem(DateTime.to_unix(timestamp), 54_321)
    }
  end

  @doc """
  Determines if the code approval have been signed by the given address

  ## Examples

      iex> %Proposal{}
      ...> |> Proposal.add_approval(
      ...>   <<0, 145, 11, 248, 77, 93, 69, 102, 3, 217, 40, 238, 90, 2, 240, 137, 127, 242, 124,
      ...>     105, 141, 192, 142, 148, 132, 159, 146, 51, 214, 138, 64, 184, 230>>
      ...> )
      ...> |> Proposal.signed_by?(
      ...>   <<0, 145, 11, 248, 77, 93, 69, 102, 3, 217, 40, 238, 90, 2, 240, 137, 127, 242, 124,
      ...>     105, 141, 192, 142, 148, 132, 159, 146, 51, 214, 138, 64, 184, 230>>
      ...> )
      true
  """
  @spec signed_by?(t(), binary()) :: boolean()
  def signed_by?(%__MODULE__{approvals: approvals}, address) do
    address in approvals
  end
end
