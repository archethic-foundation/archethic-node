defmodule Archethic.Mining.Fee do
  @moduledoc """
  Manage the transaction fee calculcation
  """
  alias Archethic.Bootstrap

  alias Archethic.Election

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract

  alias Archethic.P2P

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  @unit_uco 100_000_000

  @doc """
  Determine the fee to paid for the given transaction

  The fee will differ according to the transaction type and complexity
  Genesis, network and wallet transaction cost nothing.

  """
  @spec calculate(
          transaction :: Transaction.t(),
          uco_usd_price :: float(),
          timestamp :: DateTime.t()
        ) :: non_neg_integer()
  def calculate(%Transaction{type: :keychain}, _, _), do: 0
  def calculate(%Transaction{type: :keychain_access}, _, _), do: 0

  def calculate(
        tx = %Transaction{
          address: address,
          type: type
        },
        uco_price_in_usd,
        timestamp
      ) do
    cond do
      address == Bootstrap.genesis_address() ->
        0

      true == Transaction.network_type?(type) ->
        0

      true ->
        nb_recipients = get_number_recipients(tx)
        nb_bytes = get_transaction_size(tx)
        nb_storage_nodes = get_number_replicas(tx, timestamp)

        storage_cost =
          fee_for_storage(
            uco_price_in_usd,
            nb_bytes,
            nb_storage_nodes
          )

        replication_cost = cost_per_recipients(nb_recipients, uco_price_in_usd)

        fee =
          minimum_fee(uco_price_in_usd) + storage_cost + replication_cost +
            get_additional_fee(tx, uco_price_in_usd) + contract_fee(tx, uco_price_in_usd)

        trunc(fee * @unit_uco)
    end
  end

  defp get_additional_fee(
         %Transaction{type: :token, data: %TransactionData{content: content}},
         uco_price_in_usd
       ) do
    with {:ok, json} <- Jason.decode(content),
         "non-fungible" <- Map.get(json, "type", "fungible"),
         utxos when is_list(utxos) <- Map.get(json, "collection"),
         nb_utxos when nb_utxos > 0 <- length(utxos) do
      base_fee = minimum_fee(uco_price_in_usd)
      (:math.log10(nb_utxos) + 1) * nb_utxos * base_fee
    else
      {:error, _} ->
        0

      _ ->
        1 * minimum_fee(uco_price_in_usd)
    end
  end

  defp get_additional_fee(_tx, _uco_price_usd), do: 0

  defp get_transaction_size(
         tx = %Transaction{validation_stamp: %ValidationStamp{protocol_version: 1}}
       ) do
    tx
    |> Transaction.to_pending()
    |> Transaction.serialize()
    |> byte_size()
  end

  defp get_transaction_size(%Transaction{version: version, data: tx_data}) do
    tx_data
    |> TransactionData.serialize(version)
    |> byte_size()
  end

  defp get_number_recipients(%Transaction{
         data: %TransactionData{
           ledger: %Ledger{
             uco: %UCOLedger{transfers: uco_transfers},
             token: %TokenLedger{transfers: token_transfers}
           }
         }
       }) do
    (uco_transfers ++ token_transfers)
    |> Enum.uniq_by(& &1.to)
    |> length()
  end

  defp get_number_replicas(%Transaction{address: address}, timestamp) do
    address
    |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes(timestamp))
    |> length()
  end

  defp minimum_fee(uco_price_in_usd) do
    0.01 / uco_price_in_usd
  end

  defp fee_for_storage(uco_price_in_usd, nb_bytes, nb_storage_nodes) do
    price_per_byte = 1.0e-8 / uco_price_in_usd
    price_per_storage_node = price_per_byte * nb_bytes
    price_per_storage_node * nb_storage_nodes
  end

  # Send transaction to a single recipient does not include an additional cost
  defp cost_per_recipients(1, _), do: 0

  # Send transaction to multiple recipients (for bulk transfers) will generate an additional cost
  # As more storage pools are required to send the transaction
  defp cost_per_recipients(nb_recipients, uco_price_in_usd) do
    nb_recipients * (0.1 / uco_price_in_usd)
  end

  defp contract_fee(%Transaction{data: %TransactionData{code: code}}, uco_price_in_usd)
       when code != "" do
    case Contracts.parse(code) do
      {:ok, %Contract{triggers: triggers}} ->
        trigger_price = Enum.count(triggers) * (0.1 * uco_price_in_usd)

        operation_price =
          Enum.reduce(triggers, 0, fn {_, ast}, acc -> acc + trigger_action_fee(ast) end) *
            uco_price_in_usd

        trigger_price + operation_price

      _ ->
        0
    end
  end

  defp contract_fee(_, _), do: 0

  defp trigger_action_fee(ast) do
    Macro.prewalk(ast, 0, fn node, acc ->
      acc + op_cost(node)
    end) * 0.0001
  end

  defp op_cost({:+, _, _}), do: 1
  defp op_cost({:-, _, _}), do: 1
  defp op_cost({:/, _, _}), do: 3
  defp op_cost({:*, _, _}), do: 3
  defp op_cost({:<=, _, _}), do: 1
  defp op_cost({:<, _, _}), do: 1
  defp op_cost({:>=, _, _}), do: 1
  defp op_cost({:>, _, _}), do: 1
  defp op_cost({:or, _, _}), do: 1
  defp op_cost({:and, _, _}), do: 1
  defp op_cost({:==, _, _}), do: 1
  defp op_cost({:if, _, _}), do: 10
  defp op_cost({:else, _, _}), do: 10
  defp op_cost(op) when is_boolean(op), do: 1
  defp op_cost(op) when is_number(op), do: 1
  defp op_cost(op) when is_binary(op), do: byte_size(op)

  # String interpolation
  defp op_cost({:<<>>, _, _}), do: 1
  defp op_cost({:"::", _, _}), do: 1
  defp op_cost({:., _, [Kernel, :to_string]}), do: 1

  # Library functions
  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :hash], _, _}), do: 20
  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :regex_match?], _, _}), do: 15
  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :regex_extract], _, _}), do: 15

  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :json_path_match?], _, _}),
    do: 15

  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :size], _, _}), do: 50
  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :in?], _, _}), do: 50

  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :get_genesis_address], _, _}),
    do: 100

  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :get_genesis_public_key], _, _}),
    do: 100

  defp op_cost({:., _, [{:__aliases__, _, [:Library]}, _, :timestamp], _, _}), do: 3

  defp op_cost({:., _, [{:__aliases__, _, [:TransactionStatement]}, _, :set_content], _, _}),
    do: 10

  defp op_cost({:., _, [{:__aliases__, _, [:TransactionStatement]}, _, :set_code], _, _}),
    do: 10

  defp op_cost({:., _, [{:__aliases__, _, [:TransactionStatement]}, _, :add_uco_transfer], _, _}),
    do: 30

  defp op_cost(
         {:., _, [{:__aliases__, _, [:TransactionStatement]}, _, :add_token_transfer], _, _}
       ),
       do: 30

  defp op_cost({:., _, [{:__aliases__, _, [:TransactionStatement]}, _, :add_recipient], _, _}),
    do: 20

  defp op_cost({:., _, [{:__aliases__, _, [:TransactionStatement]}, _, :add_ownership], _, _}),
    do: 30

  # Skip the transaction assignation
  defp op_cost({:=, _, [{:scope, _, _}, {:update_in, _, _}]}), do: 0
  defp op_cost({:update_in, _, _}), do: 0
  defp op_cost({:&, _, _}), do: 0

  defp op_cost(_), do: 1
end
