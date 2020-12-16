defmodule Uniris.Contracts.Contract.Constants do
  @moduledoc """
  Represents the smart contract constants and bindings
  """

  defstruct [:contract, :transaction]

  @type t :: %__MODULE__{
          contract: Keyword.t(),
          transaction: Keyword.t() | nil
        }

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.NFTLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger

  @doc """
  Extract constants from a transaction into a list
  """
  @spec from_transaction(Transaction.t()) :: Keyword.t()
  def from_transaction(%Transaction{
        address: address,
        previous_public_key: previous_public_key,
        data: %TransactionData{
          content: content,
          code: code,
          keys: %Keys{
            authorized_keys: authorized_keys,
            secret: secret
          },
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: uco_transfers
            },
            nft: %NFTLedger{
              transfers: nft_transfers
            }
          },
          recipients: recipients
        }
      }) do
    [
      address: address,
      content: content,
      code: code,
      uco_transfers: uco_transfers,
      nft_transfers: nft_transfers,
      authorized_keys: authorized_keys,
      secret: secret,
      previous_public_key: previous_public_key,
      recipients: recipients,
      uco_transferred: Enum.reduce(uco_transfers, 0.0, &(&1.amount + &2)),
      nft_transferred: Enum.reduce(nft_transfers, 0.0, &(&1.amount + &2))
    ]
  end

  @doc """
  Convert the constants to the a keyword list
  """
  @spec to_list(t()) :: Keyword.t()
  def to_list(%__MODULE__{contract: contract_bindings, transaction: nil})
      when contract_bindings != nil do
    contract_bindings
  end

  def to_list(%__MODULE__{contract: nil, transaction: transaction_bindings})
      when transaction_bindings != nil do
    transaction_bindings
  end

  def to_list(%__MODULE__{contract: nil, transaction: nil}), do: []

  def to_list(%__MODULE__{
        contract: contract_bindings,
        transaction: transaction_bindings
      }) do
    [contract: contract_bindings, transaction: transaction_bindings]
  end
end
