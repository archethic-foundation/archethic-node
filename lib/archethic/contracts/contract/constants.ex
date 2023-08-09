defmodule Archethic.Contracts.ContractConstants do
  @moduledoc """
  Represents the smart contract constants and bindings
  """

  defstruct [:contract, :transaction]

  @type t :: %__MODULE__{
          contract: map() | nil,
          transaction: map() | nil
        }

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.Utils

  @doc """
  Extract constants from a transaction into a map
  This is a destructive operation. Some fields are not present in the resulting map.
  """
  @spec from_transaction(Transaction.t()) :: map()
  def from_transaction(%Transaction{
        address: address,
        type: type,
        previous_public_key: previous_public_key,
        data: %TransactionData{
          content: content,
          code: code,
          ownerships: ownerships,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: uco_transfers
            },
            token: %TokenLedger{
              transfers: token_transfers
            }
          },
          recipients: recipients
        },
        validation_stamp: validation_stamp
      }) do
    %{
      "address" => address,
      "type" => Atom.to_string(type),
      "content" => content,
      "code" => code,
      "authorized_keys" =>
        ownerships
        |> Enum.map(& &1.authorized_keys)
        |> Enum.flat_map(& &1),
      "authorized_public_keys" =>
        Enum.flat_map(ownerships, &Ownership.list_authorized_public_keys(&1)),
      "secrets" => Enum.map(ownerships, & &1.secret),
      "previous_public_key" => previous_public_key,
      "recipients" => Enum.map(recipients, &Recipient.get_address/1),
      "uco_transfers" =>
        Enum.reduce(uco_transfers, %{}, fn %UCOTransfer{to: to, amount: amount}, acc ->
          Map.update(acc, to, amount, &(&1 + amount))
        end),
      "uco_movements" =>
        case validation_stamp do
          nil ->
            []

          %ValidationStamp{
            ledger_operations: %LedgerOperations{transaction_movements: transaction_movements}
          } ->
            transaction_movements
            |> Enum.filter(&(&1.type == :UCO))
            |> Enum.reduce(%{}, fn %TransactionMovement{to: to, amount: amount}, acc ->
              Map.update(acc, to, amount, &(&1 + amount))
            end)
        end,
      "token_transfers" =>
        Enum.reduce(token_transfers, %{}, fn %TokenTransfer{
                                               to: to,
                                               amount: amount,
                                               token_address: token_address,
                                               token_id: token_id
                                             },
                                             acc ->
          token_transfer = %{
            "amount" => amount,
            "token_address" => token_address,
            "token_id" => token_id
          }

          Map.update(acc, to, [token_transfer], &[token_transfer | &1])
        end),
      "token_movements" =>
        case validation_stamp do
          nil ->
            []

          %ValidationStamp{
            ledger_operations: %LedgerOperations{transaction_movements: transaction_movements}
          } ->
            transaction_movements
            |> Enum.filter(&match?({:token, _, _}, &1.type))
            |> Enum.reduce(%{}, fn %TransactionMovement{
                                     to: to,
                                     amount: amount,
                                     type: {:token, token_address, token_id}
                                   },
                                   acc ->
              token_transfer = %{
                "amount" => amount,
                "token_address" => token_address,
                "token_id" => token_id
              }

              Map.update(acc, to, [token_transfer], &[token_transfer | &1])
            end)
        end,
      "timestamp" =>
        case validation_stamp do
          # Happens during the transaction validation
          nil ->
            nil

          %ValidationStamp{timestamp: timestamp} ->
            DateTime.to_unix(timestamp)
        end
    }
  end

  @doc """
  Convert a constant into transaction
  """
  @spec to_transaction(map()) :: Transaction.t()
  def to_transaction(constants) do
    %Transaction{
      address: Map.get(constants, "address"),
      type: String.to_existing_atom(Map.get(constants, "type")),
      data: %TransactionData{
        code: Map.get(constants, "code", ""),
        content: Map.get(constants, "content", ""),
        ownerships:
          constants
          |> Map.get("secrets", [])
          |> Enum.with_index()
          |> Enum.map(fn {secret, index} ->
            authorized_keys =
              constants
              |> Map.get("authorized_keys", [])
              |> Enum.map(fn {public_key, encrypted_secret_key} ->
                %{public_key => encrypted_secret_key}
              end)
              |> Enum.at(index)

            %Ownership{secret: secret, authorized_keys: authorized_keys}
          end),
        recipients: Map.get(constants, "recipients", []),
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers:
              constants
              |> Map.get("uco_transfers", [])
              |> Enum.map(fn {to, amount} ->
                %UCOTransfer{to: to, amount: amount}
              end)
          },
          token: %TokenLedger{
            transfers:
              constants
              |> Map.get("token_transfers", [])
              |> Enum.reduce([], fn {to, token_transfers}, acc ->
                token_transfers =
                  Enum.map(token_transfers, fn %{
                                                 "amount" => amount,
                                                 "token_address" => token_address,
                                                 "token_id" => token_id
                                               } ->
                    %TokenTransfer{
                      to: to,
                      amount: amount,
                      token_address: token_address,
                      token_id: token_id
                    }
                  end)

                token_transfers ++ acc
              end)
          }
        }
      },
      previous_public_key: Map.get(constants, "previous_public_key")
    }
  end

  @doc """
  Stringify binary transaction values
  """
  @spec stringify_transaction(map()) :: map()
  def stringify_transaction(constants = %{}) do
    %{
      "address" => apply_not_nil(constants, "address", &Base.encode16/1),
      "type" => Map.get(constants, "type"),
      "content" => Map.get(constants, "content"),
      "code" => Map.get(constants, "code"),
      "authorized_keys" =>
        apply_not_nil(constants, "authorized_keys", fn authorized_keys ->
          authorized_keys
          |> Enum.map(fn {public_key, encrypted_secret_key} ->
            {Base.encode16(public_key), Base.encode16(encrypted_secret_key)}
          end)
          |> Enum.into(%{})
        end),
      "authorized_public_keys" =>
        apply_not_nil(constants, "authorized_public_keys", fn public_keys ->
          Enum.map(public_keys, &Base.encode16/1)
        end),
      "secrets" =>
        apply_not_nil(constants, "secrets", fn secrets ->
          Enum.map(secrets, &Base.encode16/1)
        end),
      "previous_public_key" => apply_not_nil(constants, "previous_public_key", &Base.encode16/1),
      "recipients" =>
        apply_not_nil(constants, "recipients", fn recipients ->
          Enum.map(recipients, &Base.encode16/1)
        end),
      "uco_transfers" => apply_not_nil(constants, "uco_transfers", &uco_movements_to_string/1),
      "uco_movements" => apply_not_nil(constants, "uco_movements", &uco_movements_to_string/1),
      "token_transfers" =>
        apply_not_nil(constants, "token_transfers", &token_movements_to_string/1),
      "token_movements" =>
        apply_not_nil(constants, "token_movements", &token_movements_to_string/1),
      "timestamp" => Map.get(constants, "timestamp")
    }
  end

  defp uco_movements_to_string(transfers) do
    transfers
    |> Enum.map(fn {to, amount} ->
      {Base.encode16(to), amount}
    end)
    |> Enum.into(%{})
  end

  defp token_movements_to_string(transfers) do
    transfers
    |> Enum.map(fn {to, transfers} ->
      {Base.encode16(to),
       Enum.map(transfers, fn transfer ->
         Map.update!(transfer, "token_address", &Base.encode16/1)
       end)}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Apply a function on all transactions of the constants map
  """
  @spec map_transactions(map(), fun()) :: map()
  def map_transactions(constants, func) do
    Enum.map(constants, fn
      {name, nil} ->
        # ex: transaction might be nil when trigger=interval|datetime
        {name, nil}

      # conditions constants
      {"next", map} ->
        {"next", func.(map)}

      {"previous", map} ->
        {"previous", func.(map)}

      # both
      {"transaction", map} ->
        {"transaction", func.(map)}

      {"contract", map} ->
        {"contract", func.(map)}

      other ->
        other
    end)
    |> Enum.into(%{})
  end

  @doc """
  Divide every transfers' amount by 100_000_000 so the user can use `amount: 1` for 1 UCO/Token
  """
  @spec cast_transaction_amount_to_float(map()) :: map()
  def cast_transaction_amount_to_float(transaction) do
    transaction
    |> Map.update!("uco_transfers", &cast_uco_movements_to_float/1)
    |> Map.update!("uco_movements", &cast_uco_movements_to_float/1)
    |> Map.update!("token_transfers", &cast_token_movements_to_float/1)
    |> Map.update!("token_movements", &cast_token_movements_to_float/1)
  end

  defp cast_uco_movements_to_float(movements) do
    movements
    |> Enum.map(fn {address, amount} ->
      {address, Utils.from_bigint(amount)}
    end)
    |> Enum.into(%{})
  end

  defp cast_token_movements_to_float(movements) do
    movements
    |> Enum.map(fn {address, token_transfer} ->
      {address, Enum.map(token_transfer, &convert_token_transfer_amount_to_bigint/1)}
    end)
    |> Enum.into(%{})
  end

  defp convert_token_transfer_amount_to_bigint(token_transfer) do
    Map.update!(token_transfer, "amount", &Utils.from_bigint/1)
  end

  defp apply_not_nil(map, key, fun) do
    case Map.get(map, key) do
      nil ->
        nil

      val ->
        fun.(val)
    end
  end
end
