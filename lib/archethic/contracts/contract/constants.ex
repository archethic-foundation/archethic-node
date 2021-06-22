defmodule ArchEthic.Contracts.Contract.Constants do
  @moduledoc """
  Represents the smart contract constants and bindings
  """

  defstruct [:contract, :transaction]

  @type t :: %__MODULE__{
          contract: map(),
          transaction: map() | nil
        }

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Keys
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger

  @doc """
  Extract constants from a transaction into a map
  """
  @spec from_transaction(Transaction.t()) :: map()
  def from_transaction(%Transaction{
        address: address,
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
    %{
      "address" => address,
      "type" => Atom.to_string(type),
      "content" => content,
      "code" => code,
      "authorized_keys" => Map.keys(authorized_keys),
      "secret" => secret,
      "previous_public_key" => previous_public_key,
      "recipients" => recipients,
      "uco_transfers" =>
        uco_transfers
        |> Enum.map(fn %UCOLedger.Transfer{to: to, amount: amount} -> {to, amount} end)
        |> Enum.into(%{}),
      "nft_transfers" =>
        nft_transfers
        |> Enum.map(fn %NFTLedger.Transfer{
                         to: to,
                         amount: amount,
                         nft: nft_address
                       } ->
          {to, %{"amount" => amount, "nft" => nft_address}}
        end)
        |> Enum.into(%{})
    }
  end
end
