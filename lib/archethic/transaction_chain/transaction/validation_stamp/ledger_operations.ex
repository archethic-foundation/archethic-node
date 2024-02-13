defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Represents the ledger operations defined during the transaction mining regarding the network movements
  """

  @unit_uco 100_000_000

  defstruct transaction_movements: [],
            unspent_outputs: [],
            fee: 0,
            consumed_inputs: []

  alias Archethic.Contracts.Contract.Context, as: ContractContext
  alias Archethic.Contracts.Contract.State

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Utils.VarInt

  @typedoc """
  - Transaction movements: represents the pending transaction ledger movements
  - Unspent outputs: represents the new unspent outputs
  - fee: represents the transaction fee
  - Consumed inputs: represents the list of inputs consumed to produce the unspent outputs
  """
  @type t() :: %__MODULE__{
          transaction_movements: list(TransactionMovement.t()),
          unspent_outputs: list(UnspentOutput.t()),
          fee: non_neg_integer(),
          consumed_inputs: list(VersionedUnspentOutput.t())
        }

  @burning_address <<0::8, 0::8, 0::256>>

  @doc """
  Return the address used for the burning
  """
  @spec burning_address() :: Crypto.versioned_hash()
  def burning_address, do: @burning_address

  @doc ~S"""
  Build some ledger operations from a specific transaction
  """
  @spec get_utxos_from_transaction(
          tx :: Transaction.t(),
          validation_time :: DateTime.t(),
          protocol_version :: non_neg_integer()
        ) :: list(VersionedUnspentOutput.t())
  def get_utxos_from_transaction(
        %Transaction{
          address: address,
          type: type,
          data: %TransactionData{content: content}
        },
        timestamp,
        protocol_version
      )
      when type in [:token, :mint_rewards] and not is_nil(timestamp) do
    case Jason.decode(content) do
      {:ok, json} ->
        json
        |> get_token_utxos(address, timestamp)
        |> VersionedUnspentOutput.wrap_unspent_outputs(protocol_version)

      _ ->
        []
    end
  end

  def get_utxos_from_transaction(%Transaction{}, _timestamp, _), do: []

  defp get_token_utxos(
         %{"token_reference" => token_ref, "supply" => supply},
         address,
         timestamp
       )
       when is_binary(token_ref) and is_integer(supply) do
    case Base.decode16(token_ref, case: :mixed) do
      {:ok, token_address} ->
        [
          %UnspentOutput{
            from: address,
            amount: supply,
            type: {:token, token_address, 0},
            timestamp: timestamp
          }
        ]

      _ ->
        []
    end
  end

  defp get_token_utxos(
         %{"type" => "fungible", "supply" => supply},
         address,
         timestamp
       ) do
    [
      %UnspentOutput{
        from: address,
        amount: supply,
        type: {:token, address, 0},
        timestamp: timestamp
      }
    ]
  end

  defp get_token_utxos(
         %{
           "type" => "non-fungible",
           "supply" => supply,
           "collection" => collection
         },
         address,
         timestamp
       ) do
    if length(collection) == supply / @unit_uco do
      collection
      |> Enum.with_index()
      |> Enum.map(fn {item_properties, index} ->
        token_id = Map.get(item_properties, "id", index + 1)

        %UnspentOutput{
          from: address,
          amount: 1 * @unit_uco,
          type: {:token, address, token_id},
          timestamp: timestamp
        }
      end)
    else
      []
    end
  end

  defp get_token_utxos(
         %{"type" => "non-fungible", "supply" => @unit_uco},
         address,
         timestamp
       ) do
    [
      %UnspentOutput{
        from: address,
        amount: 1 * @unit_uco,
        type: {:token, address, 1},
        timestamp: timestamp
      }
    ]
  end

  defp get_token_utxos(_, _, _), do: []

  defp total_to_spend(fee, movements) do
    Enum.reduce(movements, %{uco: fee, token: %{}}, fn
      %TransactionMovement{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %TransactionMovement{type: {:token, token_address, token_id}, amount: amount}, acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))

      _, acc ->
        acc
    end)
  end

  defp ledger_balances(utxos) do
    Enum.reduce(utxos, %{uco: 0, token: %{}}, fn
      %VersionedUnspentOutput{unspent_output: %UnspentOutput{type: :UCO, amount: amount}}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{type: {:token, token_address, token_id}, amount: amount}
      },
      acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))

      _, acc ->
        acc
    end)
  end

  defp sufficient_funds?(uco_balance, uco_to_spend, tokens_balance, tokens_to_spend) do
    uco_balance >= uco_to_spend and sufficient_tokens?(tokens_balance, tokens_to_spend)
  end

  defp sufficient_tokens?(tokens_received = %{}, token_to_spend = %{})
       when map_size(tokens_received) == 0 and map_size(token_to_spend) > 0,
       do: false

  defp sufficient_tokens?(_tokens_received, tokens_to_spend) when map_size(tokens_to_spend) == 0,
    do: true

  defp sufficient_tokens?(tokens_received, tokens_to_spend) do
    Enum.all?(tokens_to_spend, fn {token_key, amount_to_spend} ->
      case Map.get(tokens_received, token_key) do
        nil ->
          false

        recv_amount ->
          recv_amount >= amount_to_spend
      end
    end)
  end

  @doc """
  Use the necessary inputs to satisfy the uco amount to spend
  The remaining unspent outputs will go to the change address
  Also return a boolean indicating if there was sufficient funds
  """
  @spec consume_inputs(
          ledger_operations :: t(),
          change_address :: binary(),
          timestamp :: DateTime.t(),
          inputs :: list(VersionedUnspentOutput.t()),
          movements :: list(TransactionMovement.t()),
          token_to_mint :: list(VersionedUnspentOutput.t()),
          encoded_state :: State.encoded() | nil,
          contract_context :: ContractContext.t() | nil
        ) ::
          {sufficient_funds? :: boolean(), ledger_operations :: t()}
  def consume_inputs(
        ops = %__MODULE__{fee: fee},
        change_address,
        timestamp = %DateTime{},
        inputs \\ [],
        movements \\ [],
        tokens_to_mint \\ [],
        encoded_state \\ nil,
        contract_context \\ nil
      ) do
    # Since AEIP-19 we can consume from minted tokens
    # Sort inputs, to have consistent results across all nodes
    consolidated_inputs =
      Enum.sort_by(
        tokens_to_mint ++ inputs,
        &{DateTime.to_unix(&1.unspent_output.timestamp), &1.unspent_output.from}
      )
      |> Enum.map(fn
        utxo = %UnspentOutput{from: ^change_address} ->
          # As the minted tokens are used internally during transaction's validation
          # and doesn't not exists outside, we use the burning address
          # to identify inputs coming from the token's minting.
          %{utxo | from: burning_address()}

        utxo ->
          utxo
      end)

    %{uco: uco_balance, token: tokens_balance} = ledger_balances(consolidated_inputs)
    %{uco: uco_to_spend, token: tokens_to_spend} = total_to_spend(fee, movements)

    if sufficient_funds?(uco_balance, uco_to_spend, tokens_balance, tokens_to_spend) do
      consumed_utxos =
        get_inputs_to_consume(
          consolidated_inputs,
          uco_to_spend,
          tokens_to_spend,
          uco_balance,
          tokens_balance,
          encoded_state,
          contract_context
        )

      consolidated_inputs = VersionedUnspentOutput.unwrap_unspent_outputs(consolidated_inputs)

      new_unspent_outputs =
        tokens_utxos(
          tokens_balance,
          tokens_to_spend,
          tokens_to_mint,
          consolidated_inputs,
          change_address,
          timestamp
        )
        |> add_uco_utxo(consolidated_inputs, uco_balance, uco_to_spend, change_address, timestamp)
        |> Enum.filter(&(&1.amount > 0))
        |> add_state_utxo(inputs, encoded_state, change_address, timestamp)

      {true,
       ops
       |> Map.put(:unspent_outputs, new_unspent_outputs)
       |> Map.put(:consumed_inputs, consumed_utxos)}
    else
      {false, ops}
    end
  end

  defp tokens_utxos(
         tokens_balance,
         tokens_to_spend,
         tokens_to_mint,
         utxos,
         change_address,
         timestamp
       ) do
    tokens_consolidated_not_consumed =
      Enum.reduce(tokens_balance, [], fn {{token_address, token_id}, amount}, acc ->
        if Map.has_key?(tokens_to_spend, {token_address, token_id}) do
          acc
        else
          type = {:token, token_address, token_id}

          case Enum.find(
                 utxos,
                 &(&1.type == type and &1.amount == amount)
               ) do
            nil ->
              [
                %UnspentOutput{
                  from: change_address,
                  amount: amount,
                  type: type,
                  timestamp: timestamp
                }
                | acc
              ]

            _ ->
              acc
          end
        end
      end)

    tokens_minted_not_consumed =
      Enum.reject(tokens_to_mint, fn %UnspentOutput{type: {:token, token_address, token_id}} ->
        Map.has_key?(tokens_to_spend, {token_address, token_id})
      end)

    # consolidate the remainders of spent tokens
    Enum.reduce(
      tokens_to_spend,
      tokens_minted_not_consumed ++ tokens_consolidated_not_consumed,
      fn {{token_address, token_id}, amount_to_spend}, acc ->
        balance = Map.get(tokens_balance, {token_address, token_id})
        type = {:token, token_address, token_id}
        remaining_amount = balance - amount_to_spend

        case Enum.find(
               utxos,
               &(&1.type == type and &1.amount == remaining_amount)
             ) do
          nil ->
            [
              %UnspentOutput{
                from: change_address,
                amount: remaining_amount,
                type: type,
                timestamp: timestamp
              }
              | acc
            ]

          _ ->
            acc
        end
      end
    )
  end

  defp get_inputs_to_consume(
         inputs,
         uco_to_spend,
         tokens_to_spend,
         uco_balance,
         tokens_balance,
         encoded_state,
         contract_context
       ) do
    inputs
    # We group by type to count them and determine if we need to consume the inputs
    |> Enum.group_by(& &1.unspent_output.type)
    |> Enum.flat_map(fn
      {:UCO, inputs} ->
        get_uco_to_consume(inputs, uco_to_spend, uco_balance)

      {{:token, token_address, token_id}, inputs} ->
        key = {token_address, token_id}
        get_token_to_consume(inputs, key, tokens_to_spend, tokens_balance)

      {:state,
       [
         state_utxo = %VersionedUnspentOutput{
           unspent_output: %UnspentOutput{encoded_payload: previous_state}
         }
       ]} ->
        if encoded_state != nil && previous_state != encoded_state, do: [state_utxo], else: []

      {:call, inputs} ->
        get_call_to_consume(inputs, contract_context)
    end)
  end

  defp get_uco_to_consume(inputs, uco_to_spend, uco_balance) when uco_to_spend > 0,
    do: optimize_inputs_to_consume(inputs, uco_to_spend, uco_balance)

  # The consolidation happens when there are at least more than one UTXO of the same type
  # This reduces the storage size on both genesis's inputs and further transactions
  defp get_uco_to_consume(inputs, _, _) when length(inputs) > 1, do: inputs
  defp get_uco_to_consume(_, _, _), do: []

  defp get_token_to_consume(inputs, key, tokens_to_spend, tokens_balance)
       when is_map_key(tokens_to_spend, key) do
    amount_to_spend = Map.get(tokens_to_spend, key)
    token_balance = Map.get(tokens_balance, key)
    optimize_inputs_to_consume(inputs, amount_to_spend, token_balance)
  end

  defp get_token_to_consume(inputs, _, _, _) when length(inputs) > 1, do: inputs
  defp get_token_to_consume(_, _, _, _), do: []

  defp get_call_to_consume(inputs, %ContractContext{trigger: {:transaction, address, _}}) do
    case Enum.find(inputs, &(&1.unspent_output.from == address)) do
      nil -> []
      contract_call_input -> [contract_call_input]
    end
  end

  defp get_call_to_consume(_, _), do: []

  defp optimize_inputs_to_consume(inputs, _, _) when length(inputs) == 1, do: inputs

  defp optimize_inputs_to_consume(inputs, amount_to_spend, balance_amount)
       when balance_amount == amount_to_spend,
       do: inputs

  defp optimize_inputs_to_consume(inputs, amount_to_spend, balance_amount) do
    # Search if we can consume all inputs except one. This will avoid doing consolidation
    remaining_amount = balance_amount - amount_to_spend

    case Enum.find(inputs, &(&1.unspent_output.amount == remaining_amount)) do
      nil -> inputs
      input -> Enum.reject(inputs, &(&1 == input))
    end
  end

  defp add_uco_utxo(utxos, inputs, uco_balance, uco_to_spend, change_address, timestamp)
       when uco_to_spend > 0 do
    remaining_uco = uco_balance - uco_to_spend

    case Enum.find(inputs, &(&1.type == :UCO and &1.amount == remaining_uco)) do
      nil ->
        [
          %UnspentOutput{
            from: change_address,
            amount: remaining_uco,
            type: :UCO,
            timestamp: timestamp
          }
          | utxos
        ]

      _ ->
        utxos
    end
  end

  defp add_uco_utxo(utxos, _, _, _, _, _), do: utxos

  defp add_state_utxo(utxos, _inputs, nil, _change_address, _timestamp), do: utxos

  defp add_state_utxo(utxos, inputs, encoded_state, change_address, timestamp) do
    include_new_state? =
      case Enum.find(inputs, &(&1.type == :state)) do
        nil ->
          true

        %UnspentOutput{encoded_payload: previous_encoded_state} ->
          encoded_state != previous_encoded_state
      end

    if include_new_state? do
      [
        %UnspentOutput{
          type: :state,
          encoded_payload: encoded_state,
          timestamp: timestamp,
          from: change_address
        }
        | utxos
      ]
    else
      utxos
    end
  end

  @doc """
  Build the resolved view of the movement, with the resolved address
  and convert MUCO movement to UCO movement
  """
  @spec build_resolved_movements(
          ops :: t(),
          movements :: list(TransactionMovement.t()),
          resolved_addresses :: %{Crypto.prepended_hash() => Crypto.prepended_hash()},
          tx_type :: Transaction.transaction_type()
        ) :: t()
  def build_resolved_movements(ops, movements, resolved_addresses, tx_type) do
    resolved_movements =
      movements
      |> TransactionMovement.resolve_addresses(resolved_addresses)
      |> Enum.map(&TransactionMovement.maybe_convert_reward(&1, tx_type))
      |> TransactionMovement.aggregate()

    %__MODULE__{ops | transaction_movements: resolved_movements}
  end

  @doc """
  List all the addresses from transaction movements
  """
  @spec movement_addresses(t()) :: list(binary())
  def movement_addresses(%__MODULE__{
        transaction_movements: transaction_movements
      }) do
    Enum.map(transaction_movements, & &1.to)
  end

  @doc """
  Serialize a ledger operations
  """
  @spec serialize(ledger_operations :: t(), protocol_version :: non_neg_integer()) :: bitstring()
  def serialize(
        %__MODULE__{
          fee: fee,
          transaction_movements: transaction_movements,
          unspent_outputs: unspent_outputs,
          consumed_inputs: consumed_inputs
        },
        protocol_version
      ) do
    bin_transaction_movements =
      transaction_movements
      |> Enum.map(&TransactionMovement.serialize(&1, protocol_version))
      |> :erlang.list_to_binary()

    bin_unspent_outputs =
      unspent_outputs
      |> Enum.map(&UnspentOutput.serialize(&1, protocol_version))
      |> :erlang.list_to_bitstring()

    encoded_transaction_movements_len = transaction_movements |> length() |> VarInt.from_value()
    encoded_unspent_outputs_len = unspent_outputs |> length() |> VarInt.from_value()

    consumed_inputs_bin =
      if protocol_version < 7 do
        <<>>
      else
        encoded_consumed_inputs_len = consumed_inputs |> length() |> VarInt.from_value()

        bin_consumed_inputs =
          consumed_inputs
          |> Enum.map(&VersionedUnspentOutput.serialize/1)
          |> :erlang.list_to_bitstring()

        <<encoded_consumed_inputs_len::binary, bin_consumed_inputs::bitstring>>
      end

    <<fee::64, encoded_transaction_movements_len::binary, bin_transaction_movements::binary,
      encoded_unspent_outputs_len::binary, bin_unspent_outputs::bitstring,
      consumed_inputs_bin::bitstring>>
  end

  @doc """
  Deserialize an encoded ledger operations
  """
  @spec deserialize(data :: bitstring(), protocol_version :: non_neg_integer()) ::
          {t(), bitstring()}
  def deserialize(<<fee::64, rest::bitstring>>, protocol_version) when protocol_version < 7 do
    {nb_transaction_movements, rest} = VarInt.get_value(rest)

    {tx_movements, rest} =
      deserialiaze_transaction_movements(rest, nb_transaction_movements, [], protocol_version)

    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, rest} =
      deserialize_unspent_outputs(rest, nb_unspent_outputs, [], protocol_version)

    {
      %__MODULE__{
        fee: fee,
        transaction_movements: tx_movements,
        unspent_outputs: unspent_outputs,
        consumed_inputs: []
      },
      rest
    }
  end

  def deserialize(<<fee::64, rest::bitstring>>, protocol_version) do
    {nb_transaction_movements, rest} = VarInt.get_value(rest)

    {tx_movements, rest} =
      deserialiaze_transaction_movements(rest, nb_transaction_movements, [], protocol_version)

    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, rest} =
      deserialize_unspent_outputs(rest, nb_unspent_outputs, [], protocol_version)

    {nb_consumed_inputs, rest} = rest |> VarInt.get_value()

    {consumed_inputs, rest} = deserialize_versioned_unspent_outputs(rest, nb_consumed_inputs, [])

    {
      %__MODULE__{
        fee: fee,
        transaction_movements: tx_movements,
        unspent_outputs: unspent_outputs,
        consumed_inputs: consumed_inputs
      },
      rest
    }
  end

  defp deserialiaze_transaction_movements(rest, 0, _, _), do: {[], rest}

  defp deserialiaze_transaction_movements(rest, nb, acc, _) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp deserialiaze_transaction_movements(rest, nb, acc, protocol_version) do
    {tx_movement, rest} = TransactionMovement.deserialize(rest, protocol_version)
    deserialiaze_transaction_movements(rest, nb, [tx_movement | acc], protocol_version)
  end

  defp deserialize_unspent_outputs(rest, 0, _, _), do: {[], rest}

  defp deserialize_unspent_outputs(rest, nb, acc, _) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_unspent_outputs(rest, nb, acc, protocol_version) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest, protocol_version)
    deserialize_unspent_outputs(rest, nb, [unspent_output | acc], protocol_version)
  end

  defp deserialize_versioned_unspent_outputs(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_unspent_outputs(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_unspent_outputs(
         rest,
         nb_unspent_outputs,
         acc
       ) do
    {unspent_output, rest} = VersionedUnspentOutput.deserialize(rest)

    deserialize_versioned_unspent_outputs(rest, nb_unspent_outputs, [unspent_output | acc])
  end

  @spec cast(map()) :: t()
  def cast(ledger_ops = %{}) do
    %__MODULE__{
      transaction_movements:
        ledger_ops
        |> Map.get(:transaction_movements, [])
        |> Enum.map(&TransactionMovement.cast/1),
      unspent_outputs:
        ledger_ops
        |> Map.get(:unspent_outputs, [])
        |> Enum.map(&UnspentOutput.cast/1),
      fee: Map.get(ledger_ops, :fee),
      consumed_inputs:
        ledger_ops
        |> Map.get(:consumed_inputs, [])
        |> Enum.map(&VersionedUnspentOutput.cast/1)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{
        transaction_movements: transaction_movements,
        unspent_outputs: unspent_outputs,
        fee: fee,
        consumed_inputs: consumed_inputs
      }) do
    %{
      transaction_movements: Enum.map(transaction_movements, &TransactionMovement.to_map/1),
      unspent_outputs: Enum.map(unspent_outputs, &UnspentOutput.to_map/1),
      fee: fee,
      consumed_inputs: Enum.map(consumed_inputs, &VersionedUnspentOutput.to_map/1)
    }
  end
end
