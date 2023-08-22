defmodule Archethic.Mining.Fee do
  @moduledoc """
  Manage the transaction fee calculcation
  """
  alias Archethic.Bootstrap

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  @unit_uco 100_000_000
  @token_creation_schema :archethic
                         |> Application.app_dir("priv/json-schemas/token-core.json")
                         |> File.read!()
                         |> Jason.decode!()
                         |> ExJsonSchema.Schema.resolve()

  @token_resupply_schema :archethic
                         |> Application.app_dir("priv/json-schemas/token-resupply.json")
                         |> File.read!()
                         |> Jason.decode!()
                         |> ExJsonSchema.Schema.resolve()

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

        # TODO: determine the fee for smart contract execution

        storage_cost =
          fee_for_storage(
            uco_price_in_usd,
            nb_bytes,
            nb_storage_nodes
          )

        replication_cost = cost_per_recipients(nb_recipients, uco_price_in_usd)

        fee =
          minimum_fee(uco_price_in_usd) + storage_cost + replication_cost +
            get_additional_fee(tx, uco_price_in_usd)

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

  defp get_transaction_size(%Transaction{version: version, data: tx_data}) do
    tx_data
    |> TransactionData.serialize(version)
    |> byte_size()
  end

  defp get_number_recipients(
         tx = %Transaction{
           data: %TransactionData{
             ledger: %Ledger{
               uco: %UCOLedger{transfers: uco_transfers},
               token: %TokenLedger{transfers: token_transfers}
             }
           }
         }
       ) do
    uco_transfers_addresses = uco_transfers |> Enum.map(& &1.to)
    token_transfers_addresses = token_transfers |> Enum.map(& &1.to)
    token_recipients_addresses = get_token_recipients(tx) |> Enum.map(& &1["to"])

    (uco_transfers_addresses ++ token_transfers_addresses ++ token_recipients_addresses)
    |> Enum.uniq()
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

  defp get_token_recipients(%Transaction{
         type: :token,
         data: %TransactionData{content: content}
       }) do
    case Jason.decode(content) do
      {:ok, json} ->
        cond do
          ExJsonSchema.Validator.valid?(@token_creation_schema, json) ->
            get_token_recipients_from_json(json)

          ExJsonSchema.Validator.valid?(@token_resupply_schema, json) ->
            get_token_recipients_from_json(json)

          true ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp get_token_recipients(_tx), do: []

  defp get_token_recipients_from_json(%{"recipients" => recipients}), do: recipients
  defp get_token_recipients_from_json(_json), do: []
end
