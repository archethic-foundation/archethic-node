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

  defp total_to_spend(fee, movements) do
    ledger_balances(movements, %{uco: fee, token: %{}})
  end

  defp ledger_balances(movements, acc \\ %{uco: 0, token: %{}}) do
    Enum.reduce(movements, acc, fn
      %{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %{type: {:token, token_address, token_id}, amount: amount}, acc ->
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

  ## Examples

      iex> %LedgerOperations{}
      ...> |> LedgerOperations.consume_inputs("@Alice2",  ~U[2023-09-04 00:10:00Z],
      ...>  [%UnspentOutput{from: "Charlie5", amount: 500_000_000, type: :UCO}, %UnspentOutput{from: "Tom5", amount: 100_000_000, type: :UCO}],
      ...>  [ %TransactionMovement{to: "@Bob3", amount: 100_000_000, type: :UCO}]
      ...> )
      {true, %LedgerOperations{
        unspent_outputs: [%UnspentOutput{amount: 500_000_000, from: "@Alice2", type: :UCO, timestamp: ~U[2023-09-04 00:10:00Z]}],
        consumed_inputs: [%UnspentOutput{from: "Charlie5", amount: 500_000_000, type: :UCO}, %UnspentOutput{from: "Tom5", amount: 100_000_000, type: :UCO}]
      } }

      iex> %LedgerOperations{}
      ...> |> LedgerOperations.consume_inputs("@Alice2", ~U[2023-09-04 00:10:00Z], [
      ...>    %UnspentOutput{from: "@Charlie0", amount: 100_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:01:00Z]},
      ...>    %UnspentOutput{from: "@Charlie1", amount: 500_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:02:00Z]},
      ...>    %UnspentOutput{from: "@Charlie2", amount: 500_000_000, type: {:token, "@token", 0}, timestamp: ~U[2023-09-04 00:03:00Z]},
      ...>    %UnspentOutput{from: "@Charlie3", amount: 1_000_000, type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:04:00Z]},
      ...>    %UnspentOutput{from: "@Charlie4", amount: 3_000_000, type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:05:00Z]}
      ...> ],
      ...> [ %TransactionMovement{to: "@Bob3", amount: 50_000_000, type: :UCO} ]
      ...> )
      {true, %LedgerOperations{
        unspent_outputs: [
          %UnspentOutput{amount: 550_000_000, from: "@Alice2", type: :UCO, timestamp: ~U[2023-09-04 00:10:00Z]},
          %UnspentOutput{amount: 4_000_000, from: "@Alice2", type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:10:00Z]},
          %UnspentOutput{amount: 500_000_000, from: "@Charlie2", type: {:token, "@token", 0}, timestamp: ~U[2023-09-04 00:03:00Z]}
        ],
        consumed_inputs: [
          %UnspentOutput{from: "@Charlie0", amount: 100_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:01:00Z]},
          %UnspentOutput{from: "@Charlie1", amount: 500_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:02:00Z]},
          %UnspentOutput{from: "@Charlie3", amount: 1_000_000, type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:04:00Z]},
          %UnspentOutput{from: "@Charlie4", amount: 3_000_000, type: {:token, "@michel", 0}, timestamp: ~U[2023-09-04 00:05:00Z]}
        ]
      }}

      iex> %LedgerOperations{ fee: 10_000_000 }
      ...> |> LedgerOperations.consume_inputs("@Alice2", ~U[2023-09-04 00:10:00Z], [
      ...>    %UnspentOutput{from: "@Alice1", amount: 100_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:01:00Z]},
      ...>    %UnspentOutput{from: "@SC1", amount: 0, type: :call, timestamp: ~U[2023-09-04 00:04:00Z]}
      ...>], [], [], nil, %Archethic.Contracts.Contract.Context{
      ...>    trigger: {:transaction, "@SC1", ""},
      ...>    status: :tx_output,
      ...>    timestamp: ~U[2023-09-04 00:05:00Z]
      ...> })
      {true, %LedgerOperations{
        fee: 10_000_000,
        unspent_outputs: [
          %UnspentOutput{amount: 90_000_000, from: "@Alice2", type: :UCO, timestamp: ~U[2023-09-04 00:10:00Z]},
        ],
        consumed_inputs: [
          %UnspentOutput{from: "@Alice1", amount: 100_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:01:00Z]},
          %UnspentOutput{from: "@SC1", amount: 0, type: :call, timestamp: ~U[2023-09-04 00:04:00Z]}
        ]
      }}

      iex> %LedgerOperations{}
      ...> |> LedgerOperations.consume_inputs("@Alice2", ~U[2023-09-04 00:10:00Z], [
      ...>    %UnspentOutput{from: "@Alice1", amount: 100_000_000, type: :UCO, timestamp: ~U[2023-09-04 00:01:00Z]},
      ...>    %UnspentOutput{from: "@Alice1", type: :state, timestamp: ~U[2023-09-04 00:01:00Z]}
      ...>], [], [], <<0, 1, 2, 3>>)
      {true, %LedgerOperations{
        unspent_outputs: [
          %UnspentOutput{from: "@Alice2", type: :state, timestamp: ~U[2023-09-04 00:10:00Z], encoded_payload: <<0, 1, 2, 3>>},
          %UnspentOutput{from: "@Alice2", type: :UCO, timestamp: ~U[2023-09-04 00:10:00Z], amount: 100_000_000 }
        ],
        consumed_inputs: [
          %UnspentOutput{from: "@Alice1", type: :state, timestamp: ~U[2023-09-04 00:01:00Z]}
        ]
      }}
  """
  @spec consume_inputs(
          ledger_operations :: t(),
          change_address :: binary(),
          timestamp :: DateTime.t(),
          inputs :: list(UnspentOutput.t()),
          movements :: list(TransactionMovement.t()),
          token_to_mint :: list(UnspentOutput.t()),
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
    consolidated_inputs = tokens_to_mint ++ inputs

    %{uco: uco_balance, token: tokens_balance} = ledger_balances(consolidated_inputs)
    %{uco: uco_to_spend, token: tokens_to_spend} = total_to_spend(fee, movements)

    if sufficient_funds?(uco_balance, uco_to_spend, tokens_balance, tokens_to_spend) do
      consumed_utxos =
        consolidated_inputs
        |> Enum.map(fn
          utxo = %UnspentOutput{from: ^change_address} ->
            # As the minted tokens are used internally during transaction's validation
            # and doesn't not exists outside, we use the burning address
            # to identify inputs coming from the token's minting.
            %{utxo | from: burning_address()}

          utxo ->
            utxo
        end)
        |> get_inputs_to_consume(
          uco_to_spend,
          tokens_to_spend,
          encoded_state,
          contract_context
        )

      # TODO: To active on the part 2 of the AEIP-21
      # replace token received by tokens in consumed_inputs in function new_token_unspent_outputs
      # to get only the new real unspent output

      unspent_tokens =
        new_token_unspent_outputs(
          tokens_balance,
          tokens_to_spend,
          change_address,
          consolidated_inputs,
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
        |> add_state_utxo(inputs, encoded_state, change_address, timestamp)

      {true,
       ops
       |> Map.put(:unspent_outputs, new_unspent_outputs)
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
        # if we can't find the original input, it means there was a merge
        # we update the utxo's from & timestamp
        Enum.find(
          inputs,
          %UnspentOutput{
            from: change_address,
            amount: amount,
            type: {:token, token_address, token_id},
            timestamp: timestamp
          },
          &(&1.type == {:token, token_address, token_id} && &1.amount == amount)
        )
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

  defp get_inputs_to_consume(
         inputs,
         uco_to_spend,
         tokens_to_spend,
         encoded_state,
         contract_context
       ) do
    inputs
    # We group by type to count them and determine if we need to consume the inputs
    |> Enum.group_by(& &1.type)
    |> Enum.flat_map(fn
      {:UCO, inputs} ->
        include_uco? = uco_to_spend > 0
        if include_uco? or consolidate_inputs?(inputs), do: inputs, else: []

      {{:token, token_address, token_id}, inputs} ->
        token_used? = Map.has_key?(tokens_to_spend, {token_address, token_id})
        if token_used? or consolidate_inputs?(inputs), do: inputs, else: []

      {:state, [state_utxo = %UnspentOutput{encoded_payload: previous_state}]} ->
        if encoded_state != nil && previous_state != encoded_state, do: [state_utxo], else: []

      {:call, inputs} ->
        get_contract_call_input(inputs, contract_context)
    end)
  end

  defp get_contract_call_input(inputs, %ContractContext{trigger: {:transaction, address, _}}) do
    case Enum.find(inputs, &(&1.from == address)) do
      nil ->
        []

      contract_call_input ->
        [contract_call_input]
    end
  end

  defp get_contract_call_input(_, _), do: []

  # The consolidation happens when there are at least more than one UTXO of the same type
  # This reduces the storage size on both genesis's inputs and further transactions
  defp consolidate_inputs?(inputs), do: length(inputs) > 1

  defp add_state_utxo(utxos, _inputs, nil, _change_address, _timestamp), do: utxos

  defp add_state_utxo(utxos, _inputs, encoded_state, change_address, timestamp) do
    [
      %UnspentOutput{
        type: :state,
        encoded_payload: encoded_state,
        timestamp: timestamp,
        from: change_address
      }
      | utxos
    ]
    # TODO: active during AEIP21 Phase2
    # include_new_state? =
    #   case Enum.find(inputs, &(&1.type == :state)) do
    #     nil ->
    #       true

    #     %UnspentOutput{encoded_payload: previous_state} ->
    #       encoded_state != previous_state
    #   end

    # if include_new_state? do
    #   [
    #     %UnspentOutput{
    #       type: :state,
    #       encoded_payload: encoded_state,
    #       timestamp: timestamp,
    #       from: change_address
    #     }
    #     | utxos
    #   ]
    # else
    #   utxos
    # end
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
      if protocol_version < 6 do
        <<>>
      else
        encoded_consumed_inputs_len = consumed_inputs |> length() |> VarInt.from_value()

        bin_consumed_inputs =
          consumed_inputs
          |> Enum.map(&UnspentOutput.serialize(&1, protocol_version))
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
  def deserialize(<<fee::64, rest::bitstring>>, protocol_version) when protocol_version < 6 do
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
