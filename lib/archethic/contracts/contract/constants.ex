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
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger.Transfer, as: NFTTransfer
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

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
          keys:
            keys = %Keys{
              authorized_keys: authorized_keys,
              secrets: secrets
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
      "authorized_public_keys" => Keys.list_authorized_public_keys(keys),
      "authorized_keys" => authorized_keys,
      "secrets" => secrets,
      "previous_public_key" => previous_public_key,
      "recipients" => recipients,
      "uco_transfers" =>
        uco_transfers
        |> Enum.map(fn %UCOTransfer{to: to, amount: amount} ->
          %{"to" => to, "amount" => amount}
        end),
      "nft_transfers" =>
        nft_transfers
        |> Enum.map(fn %NFTTransfer{
                         to: to,
                         amount: amount,
                         nft: nft_address
                       } ->
          %{"to" => to, "amount" => amount, "nft" => nft_address}
        end)
    }
  end

  @doc """
  Convert a constant into transaction
  """
  @spec to_transaction(map()) :: Transaction.t()
  def to_transaction(constants) do
    %Transaction{
      address: Map.get(constants, "address"),
      type: Map.get(constants, "type"),
      data: %TransactionData{
        code: Map.get(constants, "code", ""),
        content: Map.get(constants, "content", ""),
        keys: %Keys{
          authorized_keys: Map.get(constants, "authorized_keys", []),
          secrets: Map.get(constants, "secrets", [])
        },
        recipients: Map.get(constants, "recipients", []),
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers:
              constants
              |> Map.get("uco_transfers", [])
              |> Enum.map(fn %{"to" => to, "amount" => amount} ->
                %UCOTransfer{to: to, amount: amount}
              end)
          },
          nft: %NFTLedger{
            transfers:
              constants
              |> Map.get("nft_transfers", [])
              |> Enum.map(fn %{"to" => to, "amount" => amount, "nft" => nft} ->
                %NFTTransfer{to: to, amount: amount, nft: nft}
              end)
          }
        }
      },
      previous_public_key: Map.get(constants, "previous_public_key")
    }
  end
end
