defmodule Archethic.Mining.Fee do
  @moduledoc """
  Manage the transaction fee calculcation
  """
  alias Archethic.Bootstrap

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.State

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
  Return the minimum UCO amount to pay the minimum fee (equivalent of 1 cts)
  """
  @spec base_fee(uco_price_in_usd :: float()) :: non_neg_integer()
  def base_fee(uco_price_in_usd) do
    trunc(minimum_fee(uco_price_in_usd) * @unit_uco)
  end

  @doc """
  Determine the fee to paid for the given transaction

  The fee will differ according to the transaction type and complexity
  Genesis, network and wallet transaction cost nothing.

  """
  @spec calculate(
          transaction :: Transaction.t(),
          contract_context :: Contract.Context.t() | nil,
          uco_usd_price :: float(),
          timestamp :: DateTime.t(),
          encoded_state :: State.encoded() | nil,
          contract_recipient_fee :: non_neg_integer(),
          protocol_version :: pos_integer()
        ) :: non_neg_integer()
  def calculate(%Transaction{type: :keychain}, _, _, _, _, _, _), do: 0
  def calculate(%Transaction{type: :keychain_access}, _, _, _, _, _, _), do: 0
  def calculate(_, %Contract.Context{trigger: {:transaction, _, _}}, _, _, _, _, _), do: 0

  def calculate(
        %Transaction{address: address, type: type},
        _contract_context,
        _uco_price_in_usd,
        _timestamp,
        _encoded_state,
        _contract_recipient_fee,
        protocol_version
      )
      when protocol_version > 10 do
    cond do
      address == Bootstrap.genesis_address() ->
        0

      true == Transaction.network_type?(type) ->
        0

      true ->  1*@unit_uco 
    end
  end

  def calculate(
        _tx,
        _contract_context,
        _uco_price_in_usd,
        _timestamp,
        _encoded_state,
        _contract_recipient_fee,
        protocol_version
      )
      when protocol_version == 10,
      do: 0


  def calculate(
        %Transaction{address: address, type: type},
        _contract_context,
        _uco_price_in_usd,
        _timestamp,
        _encoded_state,
        _contract_recipient_fee,
        9
      ) do
    cond do
      address == Bootstrap.genesis_address() -> 0
      Transaction.network_type?(type) -> 0
      true -> 1
    end
  end

  def calculate(
        tx = %Transaction{address: address, type: type},
        _contract_context,
        uco_price_in_usd,
        timestamp,
        encoded_state,
        contract_recipient_fee,
        protocol_version
      )
      when protocol_version < 9 do
    cond do
      address == Bootstrap.genesis_address() ->
        0

      true == Transaction.network_type?(type) ->
        0

      true ->
        nb_recipients = get_number_recipients(tx)
        nb_bytes = get_transaction_size(tx) + get_state_size(encoded_state)
        nb_storage_nodes = get_number_replicas(tx, timestamp)

        # TODO: determine the fee for smart contract execution

        storage_cost =
          fee_for_storage(
            uco_price_in_usd,
            nb_bytes,
            nb_storage_nodes
          )

        replication_cost = cost_per_recipients(nb_recipients, uco_price_in_usd, protocol_version)

        fee =
          minimum_fee(uco_price_in_usd) + storage_cost + replication_cost +
            get_additional_fee(tx, uco_price_in_usd)

        trunc(fee * @unit_uco + contract_recipient_fee)
    end
  end

  defp minimum_fee(uco_price_in_usd) do
    0.01 / uco_price_in_usd
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

  defp get_state_size(nil), do: 0
  defp get_state_size(encoded_state), do: byte_size(encoded_state)

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

  defp fee_for_storage(uco_price_in_usd, nb_bytes, nb_storage_nodes) do
    price_per_byte = 1.0e-8 / uco_price_in_usd
    price_per_storage_node = price_per_byte * nb_bytes
    price_per_storage_node * nb_storage_nodes
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

  # Send transaction to a single recipient does not include an additional cost
  defp cost_per_recipients(1, _, 1), do: 0

  # Send transaction to multiple recipients (for bulk transfers) will generate an additional cost
  # As more storage pools are required to send the transaction
  defp cost_per_recipients(nb_recipients, uco_price_in_usd, 1) do
    nb_recipients * (0.1 / uco_price_in_usd)
  end

  defp cost_per_recipients(nb_recipients, uco_price_in_usd, _protocol_version)
       when nb_recipients > 0 do
    base_fee = minimum_fee(uco_price_in_usd)
    # To ensure with a simple tx, the price doesn't beyond $0.01
    # We can assume the recipient cost to replicate transaction to be something about 1/3 of the load for a given transaction
    # And we apply a logarithmic progression, as the cost of replication might be reduced by the overlap of storage node election
    (:math.log10(nb_recipients) + 0.3) * base_fee
  end

  defp cost_per_recipients(_, _, _protocol_version), do: 0

  @doc """
  Determines if a fee's variation is accepted according to 3% of slippage

  A special case is defined if the actual is 0, the expected should be 0 as well

  ## Examples

      iex> Fee.valid_variation?(0, 0)
      true

      iex> Fee.valid_variation?(0, 10)
      false

      iex> Fee.valid_variation?(100, 102)
      true

      iex> Fee.valid_variation?(98, 100)
      true

      iex> Fee.valid_variation?(100, 90)
      false
  """
  @spec valid_variation?(non_neg_integer(), non_neg_integer()) :: boolean()
  def valid_variation?(0, expected_fee), do: expected_fee == 0
  def valid_variation?(actual_fee, 0), do: actual_fee == 0

  def valid_variation?(actual_fee, expected_fee) do
    percentage_difference =
      actual_fee
      |> Decimal.sub(expected_fee)
      |> Decimal.abs()
      |> Decimal.div(
        actual_fee
        |> Decimal.add(expected_fee)
        |> Decimal.div(2)
      )
      |> Decimal.to_float()

    percentage_difference < 0.03
  end
end
