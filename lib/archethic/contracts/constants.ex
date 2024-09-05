defmodule Archethic.Contracts.Constants do
  @moduledoc """
  Represents the smart contract constants and bindings
  """

  alias Archethic.Contracts
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.UTXO

  alias Archethic.Utils

  @doc """
  Same as from_transaction but remove the contract_seed from ownerships
  """
  @spec from_contract_transaction(
          contract_tx :: Transaction.t(),
          contract_version :: non_neg_integer()
        ) ::
          map()
  def from_contract_transaction(contract_tx, contract_version \\ 1),
    do: contract_tx |> Contracts.remove_seed_ownership() |> from_transaction(contract_version)

  @doc """
  Extract constants from a transaction into a map
  This is a destructive operation. Some fields are not present in the resulting map.
  """
  @spec from_transaction(transaction :: Transaction.t(), contract_version :: non_neg_integer()) ::
          map()
  def from_transaction(
        %Transaction{
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
        },
        contract_version \\ 1
      ) do
    map = %{
      "address" => Base.encode16(address),
      "type" => Atom.to_string(type),
      "content" => content,
      "code" => code,
      "ownerships" =>
        Enum.map(ownerships, fn %Ownership{secret: secret, authorized_keys: authorized_keys} ->
          authorized_keys =
            Enum.into(authorized_keys, %{}, fn {public_key, encrypted_key} ->
              {Base.encode16(public_key), Base.encode16(encrypted_key)}
            end)

          %{"secret" => Base.encode16(secret), "authorized_keys" => authorized_keys}
        end),
      "previous_public_key" => Base.encode16(previous_public_key),
      "recipients" => Enum.map(recipients, &Base.encode16(&1.address)),
      "uco_transfers" =>
        Enum.reduce(uco_transfers, %{}, fn %UCOTransfer{to: to, amount: amount}, acc ->
          Map.update(acc, Base.encode16(to), amount, &(&1 + amount))
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
              Map.update(acc, Base.encode16(to), amount, &(&1 + amount))
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
            "token_address" => Base.encode16(token_address),
            "token_id" => token_id
          }

          Map.update(acc, Base.encode16(to), [token_transfer], &[token_transfer | &1])
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
                "token_address" => Base.encode16(token_address),
                "token_id" => token_id
              }

              Map.update(acc, Base.encode16(to), [token_transfer], &[token_transfer | &1])
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

    if contract_version == 0, do: map, else: cast_transaction_amount_to_float(map)
  end

  defp cast_transaction_amount_to_float(transaction) do
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

  @doc """
  Add balance constant based on the list of inputs
  """
  @spec set_balance(map(), list(UnspentOutput.t())) :: map()
  def set_balance(constants = %{}, inputs) do
    %{uco: uco_amount, token: tokens} = UTXO.get_balance(inputs)

    tokens =
      Enum.reduce(tokens, %{}, fn {{token_address, token_id}, amount}, acc ->
        key = %{"token_address" => Base.encode16(token_address), "token_id" => token_id}
        Map.put(acc, key, Utils.from_bigint(amount))
      end)

    balance_constants = %{"uco" => Utils.from_bigint(uco_amount), "tokens" => tokens}

    Map.put(constants, "balance", balance_constants)
  end
end
