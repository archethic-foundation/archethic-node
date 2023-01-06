defmodule Archethic.P2P.Message.GetTransactionSummary do
  @moduledoc """
  Represents a message to get a transaction summary from a transaction address
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.P2P.Message.NotFound

  @type t :: %__MODULE__{
          address: binary()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{address: address}) do
    <<23::8, address::binary>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionSummary.t() | NotFound.t()
  def process(%__MODULE__{address: address}, _) do
    case TransactionChain.get_transaction_summary(address) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        %NotFound{}
    end
  end
end
