defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Represents the ledger operations defined during the transaction mining regarding the network movements:
  - transaction movements
  - unspent outputs
  - transaction fee
  """

  @unit_uco 100_000_000

  defstruct transaction_movements: [],
            unspent_outputs: [],
            fee: 0

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
  - fee: represents the transaction fee distributed across the node movements
  """
  @type t() :: %__MODULE__{
          transaction_movements: list(TransactionMovement.t()),
          unspent_outputs: list(UnspentOutput.t()),
          fee: non_neg_integer()
        }

  @burning_address <<0::8, 0::8, 0::256>>

  @doc """
  Return the address used for the burning
  """
  @spec burning_address() :: Crypto.versioned_hash()
  def burning_address, do: @burning_address

  @doc ~S"""
  Build some ledger operations from a specific transaction
  ## Examples
      iex> LedgerOperations.from_transaction(%LedgerOperations{},
      ...>   %Transaction{
      ...>     address: "@Token2",
      ...>     type: :token,
      ...>     data: %TransactionData{content: "{\"supply\": 1000000000, \"type\": \"fungible\" }"}
      ...>   }
      ...> )
      %LedgerOperations{
          unspent_outputs: [%UnspentOutput{from: "@Token2", amount: 1000000000, type: {:token, "@Token2", 0}}]
      }

      iex> LedgerOperations.from_transaction(%LedgerOperations{},
      ...>   %Transaction{
      ...>     address: "@Token2",
      ...>     type: :token,
      ...>     data: %TransactionData{content: "{\"supply\": 1000000000, \"type\": \"non-fungible\", \"properties\": [[],[],[],[],[],[],[],[],[],[]]}"}
      ...>   }
      ...>  )
      %LedgerOperations{
        unspent_outputs: [
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 1}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 2}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 3}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 4}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 5}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 6}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 7}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 8}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 9}},
          %UnspentOutput{from: "@Token2", amount: 100_000_000, type: {:token, "@Token2", 10}}
        ]
      }
  """
  @spec from_transaction(t(), Transaction.t()) :: t()
  def from_transaction(ops = %__MODULE__{}, %Transaction{
        address: address,
        type: type,
        data: %TransactionData{content: content}
      })
      when type in [:token, :mint_rewards] do
    case Jason.decode(content) do
      {:ok, json} ->
        utxos = get_token_utxos(json, address)
        Map.update(ops, :unspent_outputs, utxos, &(utxos ++ &1))

      _ ->
        ops
    end
  end

  def from_transaction(ops = %__MODULE__{}, %Transaction{}), do: ops

  defp get_token_utxos(%{"type" => "fungible", "supply" => supply}, address) do
    [
      %UnspentOutput{
        from: address,
        amount: supply,
        type: {:token, address, 0}
      }
    ]
  end

  defp get_token_utxos(
         %{"type" => "non-fungible", "supply" => supply, "properties" => properties},
         address
       )
       when length(properties) == supply / @unit_uco do
    properties
    |> Enum.with_index()
    |> Enum.map(fn {_item_properties, index} ->
      %UnspentOutput{from: address, amount: 1 * @unit_uco, type: {:token, address, index + 1}}
    end)
  end

  defp get_token_utxos(_, _), do: []

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
    transaction_movements
    |> Enum.reject(&(&1.to == @burning_address))
    |> ledger_balances(%{uco: fee, token: %{}})
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

  ## Examples

    # When a single unspent output is sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Bob3", amount: 2_000_000_000, type: :UCO}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
            %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO}
          ],
          fee: 40_000_000,
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 703_000_000, type: :UCO}
          ]
      }

    # When multiple little unspent output are sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Bob3", amount: 500_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Tom4", amount: 700_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Christina", amount: 400_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Hugo", amount: 800_000_000, type: :UCO}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
            %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
          ],
          fee: 40_000_000,
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 1_103_000_000, type: :UCO},
          ]
      }

     # When using Token unspent outputs are sufficient to satisfy the transaction movements

       iex> %LedgerOperations{
       ...>    transaction_movements: [
       ...>      %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:token, "@CharlieToken", 0}}
       ...>    ],
       ...>    fee: 40_000_000
       ...> }
       ...> |> LedgerOperations.consume_inputs("@Alice2", [
       ...>    %UnspentOutput{from: "@Charlie1", amount: 200_000_000, type: :UCO},
       ...>    %UnspentOutput{from: "@Bob3", amount: 1_200_000_000, type: {:token, "@CharlieToken", 0}}
       ...> ])
       %LedgerOperations{
           transaction_movements: [
             %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:token, "@CharlieToken", 0}}
           ],
           fee: 40_000_000,
           unspent_outputs: [
             %UnspentOutput{from: "@Alice2", amount: 160_000_000, type: :UCO},
             %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: {:token, "@CharlieToken", 0}}
           ]
       }

    #  When multiple Token unspent outputs are sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:token, "@CharlieToken", 0}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Charlie1", amount: 200_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Bob3", amount: 500_000_000, type: {:token, "@CharlieToken", 0}},
      ...>    %UnspentOutput{from: "@Hugo5", amount: 700_000_000, type: {:token, "@CharlieToken", 0}},
      ...>    %UnspentOutput{from: "@Tom1", amount: 700_000_000, type: {:token, "@CharlieToken", 0}}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:token, "@CharlieToken", 0}}
          ],
          fee: 40_000_000,
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 160_000_000, type: :UCO},
            %UnspentOutput{from: "@Alice2", amount: 900_000_000, type: {:token, "@CharlieToken", 0}}
          ]
      }

      # When non-fungible tokens are used as input but want to consume only a single input

      iex> %LedgerOperations{
      ...>   transaction_movements: [
      ...>     %TransactionMovement{to: "@Bob4", amount: 100_000_000, type: {:token, "@CharlieToken", 2}}
      ...> ],
      ...>   fee: 40_000_000
      ...> } |> LedgerOperations.consume_inputs("@Alice2", [
      ...>     %UnspentOutput{from: "@Charlie1", amount: 200_000_000, type: :UCO},
      ...>      %UnspentOutput{from: "@CharlieToken", amount: 100_000_000, type: {:token, "@CharlieToken", 1}},
      ...>      %UnspentOutput{from: "@CharlieToken", amount: 100_000_000, type: {:token, "@CharlieToken", 2}},
      ...>      %UnspentOutput{from: "@CharlieToken", amount: 100_000_000, type: {:token, "@CharlieToken", 3}}
      ...> ])
      %LedgerOperations{
        fee: 40_000_000,
        transaction_movements: [
          %TransactionMovement{to: "@Bob4", amount: 100_000_000, type: {:token, "@CharlieToken", 2}}
        ],
        unspent_outputs: [
          %UnspentOutput{from: "@Alice2", amount: 160_000_000, type: :UCO},
          %UnspentOutput{from: "@CharlieToken", amount: 100_000_000, type: {:token, "@CharlieToken", 1}},
          %UnspentOutput{from: "@CharlieToken", amount: 100_000_000, type: {:token, "@CharlieToken", 3}}
        ]
      }
  """
  @spec consume_inputs(
          ledger_operations :: t(),
          change_address :: binary(),
          inputs :: list(UnspentOutput.t() | TransactionInput.t())
        ) ::
          t()
  def consume_inputs(ops = %__MODULE__{}, change_address, inputs)
      when is_binary(change_address) and is_list(inputs) do
    if sufficient_funds?(ops, inputs) do
      %{uco: uco_balance, token: tokens_received} = ledger_balances(inputs)
      %{uco: uco_to_spend, token: tokens_to_spend} = total_to_spend(ops)

      new_unspent_outputs = [
        %UnspentOutput{from: change_address, amount: uco_balance - uco_to_spend, type: :UCO}
        | new_token_unspent_outputs(tokens_received, tokens_to_spend, change_address, inputs)
      ]

      Map.update!(ops, :unspent_outputs, &(new_unspent_outputs ++ &1))
    else
      ops
    end
  end

  defp new_token_unspent_outputs(tokens_received, tokens_to_spend, change_address, inputs) do
    # Reject Token not used to inject back in the new unspent outputs
    tokens_not_used =
      tokens_received
      |> Enum.reject(&Map.has_key?(tokens_to_spend, elem(&1, 0)))
      |> Enum.map(fn {{token_address, token_id}, amount} ->
        Enum.find(inputs, fn input ->
          input.type == {:token, token_address, token_id} and input.amount == amount
        end)
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
              type: {:token, token_address, token_id}
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

  @doc """
  List all the addresses from transaction movements
  """
  @spec movement_addresses(t()) :: list(binary())
  def movement_addresses(%__MODULE__{
        transaction_movements: transaction_movements
      }) do
    transaction_movements
    |> Enum.reject(&(&1.to == @burning_address))
    |> Enum.map(& &1.to)
  end

  @doc """
  Serialize a ledger operations

  ## Examples

      iex> %LedgerOperations{
      ...>   fee: 10_000_000,
      ...>   transaction_movements: [
      ...>     %TransactionMovement{
      ...>       to: <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 102_000_000,
      ...>       type: :UCO
      ...>     },
      ...>   ],
      ...>   unspent_outputs: [
      ...>     %UnspentOutput{
      ...>       from: <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 200_000_000,
      ...>       type: :UCO
      ...>     }
      ...>   ]
      ...> }
      ...> |> LedgerOperations.serialize()
      <<
      # Fee (0.1 UCO)
      0, 0, 0, 0, 0, 152, 150, 128,
      # Nb of transaction movements in VarInt
      1, 1,
      # Transaction movement recipient
      0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Transaction movement amount (1.2 UCO)
      0, 0, 0, 0, 6, 20, 101, 128,
      # Transaction movement type (UCO)
      0,
      # Nb of unspent outputs in VarInt
      1, 1,
      # Unspent output origin
      0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Unspent output amount (2 UCO)
      0, 0, 0, 0, 11, 235, 194, 0,
      # Unspent output type (UCO)
      0
      >>
  """
  def serialize(%__MODULE__{
        fee: fee,
        transaction_movements: transaction_movements,
        unspent_outputs: unspent_outputs
      }) do
    bin_transaction_movements =
      transaction_movements
      |> Enum.map(&TransactionMovement.serialize/1)
      |> :erlang.list_to_binary()

    bin_unspent_outputs =
      unspent_outputs |> Enum.map(&UnspentOutput.serialize/1) |> :erlang.list_to_binary()

    encoded_transaction_movements_len = length(transaction_movements) |> VarInt.from_value()

    encoded_unspent_outputs_len = length(unspent_outputs) |> VarInt.from_value()

    <<fee::64, encoded_transaction_movements_len::binary, bin_transaction_movements::binary,
      encoded_unspent_outputs_len::binary, bin_unspent_outputs::binary>>
  end

  @doc """
  Deserialize an encoded ledger operations

  ## Examples

      iex> <<0, 0, 0, 0, 0, 152, 150, 128, 1, 1,
      ...> 0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      ...> 0, 0, 0, 0, 60, 203, 247, 0, 0,
      ...> 1, 1, 0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237,
      ...> 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      ...> 0, 0, 0, 0, 11, 235, 194, 0, 0>>
      ...> |> LedgerOperations.deserialize()
      {
        %LedgerOperations{
          fee: 10_000_000,
          transaction_movements: [
            %TransactionMovement{
              to: <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 1_020_000_000,
              type: :UCO
            }
          ],
          unspent_outputs: [
            %UnspentOutput{
              from: <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 200_000_000,
              type: :UCO
            }
          ]
        },
        ""
      }
  """
  def deserialize(<<fee::64, rest::bitstring>>) do
    {nb_transaction_movements, rest} = rest |> VarInt.get_value()
    {tx_movements, rest} = reduce_transaction_movements(rest, nb_transaction_movements, [])

    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()
    {unspent_outputs, rest} = reduce_unspent_outputs(rest, nb_unspent_outputs, [])

    {
      %__MODULE__{
        fee: fee,
        transaction_movements: tx_movements,
        unspent_outputs: unspent_outputs
      },
      rest
    }
  end

  defp reduce_transaction_movements(rest, 0, _), do: {[], rest}

  defp reduce_transaction_movements(rest, nb, acc) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_transaction_movements(rest, nb, acc) do
    {tx_movement, rest} = TransactionMovement.deserialize(rest)
    reduce_transaction_movements(rest, nb, [tx_movement | acc])
  end

  defp reduce_unspent_outputs(rest, 0, _), do: {[], rest}

  defp reduce_unspent_outputs(rest, nb, acc) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_unspent_outputs(rest, nb, acc) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest)
    reduce_unspent_outputs(rest, nb, [unspent_output | acc])
  end

  @spec from_map(map()) :: t()
  def from_map(ledger_ops = %{}) do
    %__MODULE__{
      transaction_movements:
        Map.get(ledger_ops, :transaction_movements, [])
        |> Enum.map(&TransactionMovement.from_map/1),
      unspent_outputs:
        Map.get(ledger_ops, :unspent_outputs, [])
        |> Enum.map(&UnspentOutput.from_map/1),
      fee: Map.get(ledger_ops, :fee)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{
        transaction_movements: transaction_movements,
        unspent_outputs: unspent_outputs,
        fee: fee
      }) do
    %{
      transaction_movements: Enum.map(transaction_movements, &TransactionMovement.to_map/1),
      unspent_outputs: Enum.map(unspent_outputs, &UnspentOutput.to_map/1),
      fee: fee
    }
  end

  @doc """
  Add the movement to burn the fee
  """
  @spec add_burning_movement(t()) :: t()
  def add_burning_movement(ops = %__MODULE__{}) do
    burn_movement = get_burning_movement(ops)
    Map.update(ops, :transaction_movements, [burn_movement], &([burn_movement] ++ &1))
  end

  @doc """
  Get the burning transaction movement
  """
  @spec get_burning_movement(t()) :: TransactionMovement.t()
  def get_burning_movement(%__MODULE__{fee: fee}) do
    %TransactionMovement{
      to: @burning_address,
      amount: fee,
      type: :UCO
    }
  end
end
