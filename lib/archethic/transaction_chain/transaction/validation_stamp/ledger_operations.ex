defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Represents the ledger operations defined during the transaction mining regarding the network movements
  """

  @unit_uco 100_000_000

  defstruct transaction_movements: [],
            unspent_outputs: [],
            tokens_to_mint: [],
            fee: 0,
            consumed_inputs: []

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput

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
          tokens_to_mint: list(UnspentOutput.t()),
          fee: non_neg_integer(),
          consumed_inputs: list(UnspentOutput.t())
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
  @spec get_utxos_from_transaction(Transaction.t(), DateTime.t()) :: list(UnspentOutput.t())
  def get_utxos_from_transaction(
        %Transaction{
          address: address,
          type: type,
          data: %TransactionData{content: content}
        },
        timestamp
      )
      when type in [:token, :mint_rewards] and not is_nil(timestamp) do
    case Jason.decode(content) do
      {:ok, json} ->
        get_token_utxos(json, address, timestamp)

      _ ->
        []
    end
  end

  def get_utxos_from_transaction(%Transaction{}, _timestamp), do: []

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

  @doc """
  Returns the amount to spend from the transaction movements and the fee

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 2_000_000_000, type:
      ...>      {:token, "@TomToken", 0}},
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.total_to_spend()
      %{ uco: 1_297_000_000, token: %{ {"@TomToken",0} => 2_000_000_000 } }
  """
  @spec total_to_spend(t()) :: %{
          :uco => non_neg_integer(),
          :token => %{binary() => non_neg_integer()}
        }
  def total_to_spend(%__MODULE__{transaction_movements: transaction_movements, fee: fee}) do
    ledger_balances(transaction_movements, %{uco: fee, token: %{}})
  end

  defp ledger_balances(movements, acc \\ %{uco: 0, token: %{}}) do
    Enum.reduce(movements, acc, fn
      %{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %{type: {:token, token_address, token_id}, amount: amount}, acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))

      %{type: :call}, acc ->
        acc
    end)
  end

  @doc """
  Determine if the funds are sufficient with the given unspent outputs for total of uco to spend

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Tom4", amount: 500_000_000, type: {:token, "@BobToken", 0}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([])
      false

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Tom4", amount: 500_000_000, type: {:token, "@BobToken", 0}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([
      ...>     %UnspentOutput{from: "@Charlie5", amount: 3_000_000_000, type: :UCO},
      ...>     %UnspentOutput{from: "@Bob4", amount: 1_000_000_000, type: {:token, "@BobToken", 0}}
      ...> ])
      true

      iex> %LedgerOperations{
      ...>    transaction_movements: [],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([
      ...>     %UnspentOutput{from: "@Charlie5", amount: 3_000_000_000, type: :UCO},
      ...>     %UnspentOutput{from: "@Bob4", amount: 10_000_000_000, type: {:token, "@BobToken", 0}}
      ...> ])
      true
  """
  @spec sufficient_funds?(t(), list(UnspentOutput.t() | TransactionInput.t())) :: boolean()
  def sufficient_funds?(operations = %__MODULE__{}, inputs) when is_list(inputs) do
    %{uco: uco_balance, token: tokens_received} = ledger_balances(inputs)
    %{uco: uco_to_spend, token: tokens_to_spend} = total_to_spend(operations)
    uco_balance >= uco_to_spend and sufficient_tokens?(tokens_received, tokens_to_spend)
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

  ## Examples

      iex> %LedgerOperations{
      ...>   transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob3", amount: 100_000_000, type: :UCO}
      ...>   ]
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [%UnspentOutput{from: "Charlie5", amount: 500_000_000, type: :UCO}, %UnspentOutput{from: "Tom5", amount: 100_000_000, type: :UCO}], ~U[2023-09-04 00:10:00Z])
      {true, %LedgerOperations{
        transaction_movements: [%TransactionMovement{to: "@Bob3", amount: 100000000, type: :UCO}],
        unspent_outputs: [%UnspentOutput{amount: 500000000, from: "@Alice2", type: :UCO, timestamp: ~U[2023-09-04 00:10:00Z]}],
        consumed_inputs: [%UnspentOutput{from: "Charlie5", amount: 500_000_000, type: :UCO}, %UnspentOutput{from: "Tom5", amount: 100_000_000, type: :UCO}]
      } }

      iex> %LedgerOperations{
      ...>   transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob3", amount: 50_000_000, type: :UCO},
      ...>   ]
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Charlie0", amount: 100_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:01:00Z]},
      ...>    %UnspentOutput{from: "@Charlie1", amount: 500_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:02:00Z]},
      ...>    %UnspentOutput{from: "@Charlie2", amount: 500_000_000, type: {:token, "@token", 0}, timestamp: ~U[2023-09-04 00:03:00Z]},
      ...>    %UnspentOutput{from: "@Charlie3", amount: 1_000_000, type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:04:00Z]},
      ...>    %UnspentOutput{from: "@Charlie4", amount: 3_000_000, type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:05:00Z]}
      ...>], ~U[2023-09-04 00:10:00Z])
      {true, %LedgerOperations{
        transaction_movements: [%TransactionMovement{to: "@Bob3", amount: 50000000, type: :UCO}],
        unspent_outputs: [
          %UnspentOutput{amount: 550000000, from: "@Alice2", type: :UCO, timestamp: ~U[2023-09-04 00:10:00Z]},
          %UnspentOutput{amount: 4000000, from: "@Alice2", type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:04:00Z]},
          %UnspentOutput{amount: 500000000, from: "@Charlie2", type: {:token, "@token", 0}, timestamp: ~U[2023-09-04 00:03:00Z]}
        ],
        consumed_inputs: [
          %UnspentOutput{from: "@Charlie0", amount: 100_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:01:00Z]},
          %UnspentOutput{from: "@Charlie1", amount: 500_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:02:00Z]},
          %UnspentOutput{from: "@Charlie3", amount: 1_000_000, type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:04:00Z]},
          %UnspentOutput{from: "@Charlie4", amount: 3_000_000, type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:05:00Z]}
        ]
      }}
  """
  @spec consume_inputs(
          ledger_operations :: t(),
          change_address :: binary(),
          inputs :: list(UnspentOutput.t()),
          timestamp :: DateTime.t()
        ) ::
          {sufficient_funds? :: boolean(), ledger_operations :: t()}
  def consume_inputs(
        ops = %__MODULE__{tokens_to_mint: tokens_to_mint},
        change_address,
        inputs,
        timestamp
      )
      when is_binary(change_address) and is_list(inputs) and not is_nil(timestamp) do
    # Since AEIP-19 we can consume from minted tokens
    inputs = inputs ++ tokens_to_mint

    if sufficient_funds?(ops, inputs) do
      %{uco: uco_balance, token: tokens_received} = ledger_balances(inputs)
      %{uco: uco_to_spend, token: tokens_to_spend} = total_to_spend(ops)

      consumed_utxos = get_inputs_to_consume(inputs, uco_to_spend, tokens_to_spend)

      # TODO: To active on the part 2 of the AEIP-21
      # replace token received by tokens in consumed_inputs in function new_token_unspent_outputs
      # to get only the new real unspent output

      unspent_tokens =
        new_token_unspent_outputs(
          tokens_received,
          tokens_to_spend,
          change_address,
          inputs,
          timestamp
        )

      new_unspent_outputs =
        [
          %UnspentOutput{
            from: change_address,
            amount: uco_balance - uco_to_spend,
            type: :UCO,
            timestamp: timestamp
          }
          | unspent_tokens
        ]
        |> Enum.filter(&(&1.amount > 0))

      {true,
       ops
       |> Map.put(:unspent_outputs, new_unspent_outputs)
       |> Map.put(:tokens_to_mint, [])
       |> Map.put(:consumed_inputs, consumed_utxos)}
    else
      {false, ops}
    end
  end

  defp new_token_unspent_outputs(
         tokens_received,
         tokens_to_spend,
         change_address,
         inputs,
         timestamp
       ) do
    # Reject Token not used to inject back in the new unspent outputs
    tokens_not_used =
      tokens_received
      |> Enum.reject(&Map.has_key?(tokens_to_spend, elem(&1, 0)))
      |> Enum.map(fn {{token_address, token_id}, amount} ->
        input =
          Enum.find(inputs, fn input ->
            input.type == {:token, token_address, token_id}
          end)

        if input.amount == amount,
          do: input,
          else: %{input | amount: amount, from: change_address}
      end)

    Enum.reduce(tokens_to_spend, tokens_not_used, fn {{token_address, token_id}, amount_to_spend},
                                                     acc ->
      case Map.get(tokens_received, {token_address, token_id}) do
        nil ->
          acc

        recv_amount when recv_amount - amount_to_spend > 0 ->
          [
            %UnspentOutput{
              from: change_address,
              amount: recv_amount - trunc_token_amount(token_id, amount_to_spend),
              type: {:token, token_address, token_id},
              timestamp: timestamp
            }
            | acc
          ]

        _ ->
          acc
      end
    end)
  end

  # We prevent part of non-fungible token to be spent
  defp trunc_token_amount(0, amount), do: amount
  defp trunc_token_amount(_token_id, amount), do: trunc(amount / @unit_uco) * @unit_uco

  defp get_inputs_to_consume(inputs, uco_to_spend, tokens_to_spend) do
    include_uco? = uco_to_spend > 0

    inputs
    # Sanitize data format (UTXO or Input)
    |> Enum.map(&UnspentOutput.cast/1)
    # We group by type to count them and determine if we need to consume the inputs
    |> Enum.group_by(& &1.type)
    |> Enum.filter(fn
      {:UCO, inputs} ->
        include_uco? or consolidate_inputs?(inputs)

      {{:token, token_address, token_id}, inputs} ->
        token_used?(tokens_to_spend, token_address, token_id) or consolidate_inputs?(inputs)
    end)
    |> Enum.flat_map(fn {_type, inputs} -> inputs end)
  end

  # The consolidation happens when there are at least more than one UTXO of the same type
  # This reduces the storage size on both genesis's inputs and further transactions
  defp consolidate_inputs?(inputs), do: length(inputs) > 1

  defp token_used?(tokens_to_spend, token_address, token_id) do
    Map.has_key?(tokens_to_spend, {token_address, token_id})
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
      |> :erlang.list_to_binary()

    bin_consumed_inputs =
      consumed_inputs
      |> Enum.map(&UnspentOutput.serialize(&1, protocol_version))
      |> :erlang.list_to_binary()

    encoded_transaction_movements_len = transaction_movements |> length() |> VarInt.from_value()
    encoded_unspent_outputs_len = unspent_outputs |> length() |> VarInt.from_value()
    encoded_consumed_inputs_len = consumed_inputs |> length() |> VarInt.from_value()

    <<fee::64, encoded_transaction_movements_len::binary, bin_transaction_movements::binary,
      encoded_unspent_outputs_len::binary, bin_unspent_outputs::binary,
      encoded_consumed_inputs_len::binary, bin_consumed_inputs::binary>>
  end

  @doc """
  Deserialize an encoded ledger operations
  """
  @spec deserialize(data :: bitstring(), protocol_version :: non_neg_integer()) ::
          {t(), bitstring()}
  def deserialize(<<fee::64, rest::bitstring>>, protocol_version) when protocol_version < 3 do
    {nb_transaction_movements, rest} = VarInt.get_value(rest)

    {tx_movements, rest} =
      reduce_transaction_movements(rest, nb_transaction_movements, [], protocol_version)

    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, rest} =
      reduce_unspent_outputs(rest, nb_unspent_outputs, [], protocol_version)

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
      reduce_transaction_movements(rest, nb_transaction_movements, [], protocol_version)

    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, rest} =
      reduce_unspent_outputs(rest, nb_unspent_outputs, [], protocol_version)

    {nb_consumed_inputs, rest} = rest |> VarInt.get_value()

    {consumed_inputs, rest} =
      reduce_unspent_outputs(rest, nb_consumed_inputs, [], protocol_version)

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

  defp reduce_transaction_movements(rest, 0, _, _), do: {[], rest}

  defp reduce_transaction_movements(rest, nb, acc, _) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_transaction_movements(rest, nb, acc, protocol_version) do
    {tx_movement, rest} = TransactionMovement.deserialize(rest, protocol_version)
    reduce_transaction_movements(rest, nb, [tx_movement | acc], protocol_version)
  end

  defp reduce_unspent_outputs(rest, 0, _, _), do: {[], rest}

  defp reduce_unspent_outputs(rest, nb, acc, _) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_unspent_outputs(rest, nb, acc, protocol_version) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest, protocol_version)
    reduce_unspent_outputs(rest, nb, [unspent_output | acc], protocol_version)
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
        |> Enum.map(&UnspentOutput.cast/1)
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
      consumed_inputs: Enum.map(consumed_inputs, &UnspentOutput.to_map/1)
    }
  end
end
