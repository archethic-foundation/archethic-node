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
        timestamp: timestamp,
        type: type,
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
      type: type,
      timestamp: timestamp,
      content: content,
      code: code,
      authorized_keys: authorized_keys,
      secret: secret,
      previous_public_key: previous_public_key,
      recipients: recipients,
      uco_transferred: Enum.reduce(uco_transfers, 0.0, &(&1.amount + &2)),
      nft_transferred: Enum.reduce(nft_transfers, 0.0, &(&1.amount + &2)),
      uco_transfers:
        uco_transfers
        |> Enum.map(fn %UCOLedger.Transfer{to: to, amount: amount} -> {to, amount} end)
        |> Enum.into(%{}),
      nft_transfers:
        nft_transfers
        |> Enum.map(fn %NFTLedger.Transfer{
                         to: to,
                         amount: amount,
                         nft: nft_address
                       } ->
          {to, %{amount: amount, nft: nft_address}}
        end)
        |> Enum.into(%{})
    ]
  end
end
