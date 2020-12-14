defmodule Uniris.Contracts.Contract.Constants do
  @moduledoc """
  Represents the smart contract constants
  """
  defstruct [
    :address,
    :content,
    :previous_public_key,
    :uco_transfers,
    :authorized_keys,
    :recipients
  ]

  alias Uniris.Crypto

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.NFTLedger.Transfer

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          content: binary(),
          previous_public_key: Crypto.key(),
          uco_transfers: list(Transfer.t()),
          authorized_keys: list(Crypto.key()),
          recipients: list(Crypto.versioned_hash())
        }

  @doc """
  Extracts necessary smart contract constants from transaction
  """
  @spec from_transaction(Transaction.t()) :: t()
  def from_transaction(%Transaction{
        address: address,
        previous_public_key: previous_public_key,
        data: %TransactionData{
          content: content,
          keys: keys,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: uco_transfers
            }
          },
          recipients: recipients
        }
      }) do
    %__MODULE__{
      address: address,
      content: content,
      uco_transfers: uco_transfers,
      authorized_keys: Keys.list_authorized_keys(keys),
      previous_public_key: previous_public_key,
      recipients: recipients
    }
  end
end
