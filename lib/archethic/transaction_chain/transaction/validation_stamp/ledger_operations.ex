defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Represents the ledger operations defined during the transaction mining regarding the network movements:
  - transaction movements
  - node rewards
  - unspent outputs
  - transaction fee
  """

  @unit_uco 100_000_000

  defstruct transaction_movements: [],
            unspent_outputs: [],
            fee: 0

  alias Archethic.Crypto

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput

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

  @doc """
  Build some ledger operations from a specific transaction

  ## Examples

      iex> LedgerOperations.from_transaction(%LedgerOperations{},
      ...>   %Transaction{
      ...>     address: "@NFT2",
      ...>     type: :nft,
      ...>     data: %TransactionData{content: "initial supply: 1000"}
      ...>   }
      ...> )
      %LedgerOperations{
          unspent_outputs: [%UnspentOutput{from: "@NFT2", amount: 100_000_000_000, type: {:NFT, "@NFT2"}}]
      }
  """
  @spec from_transaction(t(), Transaction.t()) :: t()
  def from_transaction(ops = %__MODULE__{}, %Transaction{
        address: address,
        type: :nft,
        data: %TransactionData{content: content}
      }) do
    [[match | _]] = Regex.scan(~r/(?<=initial supply:).*\d/mi, content)

    {initial_supply, _} =
      match
      |> String.trim()
      |> String.replace(" ", "")
      |> Integer.parse()

    %{
      ops
      | unspent_outputs: [
          %UnspentOutput{from: address, amount: initial_supply * @unit_uco, type: {:NFT, address}}
        ]
    }
  end

  def from_transaction(ops = %__MODULE__{}, %Transaction{}), do: ops

  @doc """
  Returns the amount to spend from the transaction movements and the fee

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 2_000_000_000, type: {:NFT, "@TomNFT"}},
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.total_to_spend()
      %{ uco: 1_297_000_000, nft: %{ "@TomNFT" => 2_000_000_000 } }
  """
  @spec total_to_spend(t()) :: %{
          :uco => non_neg_integer(),
          :nft => %{binary() => non_neg_integer()}
        }
  def total_to_spend(%__MODULE__{transaction_movements: transaction_movements, fee: fee}) do
    transaction_movements
    |> Enum.reject(&(&1.to == @burning_address))
    |> ledger_balances(%{uco: fee, nft: %{}})
  end

  defp ledger_balances(movements, acc \\ %{uco: 0, nft: %{}}) do
    Enum.reduce(movements, acc, fn
      %{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %{type: {:NFT, nft_address}, amount: amount}, acc ->
        update_in(acc, [:nft, Access.key(nft_address, 0)], &(&1 + amount))

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
      ...>      %TransactionMovement{to: "@Tom4", amount: 500_000_000, type: {:NFT, "@BobNFT"}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([])
      false

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Tom4", amount: 500_000_000, type: {:NFT, "@BobNFT"}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([
      ...>     %UnspentOutput{from: "@Charlie5", amount: 3_000_000_000, type: :UCO},
      ...>     %UnspentOutput{from: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@BobNFT"}}
      ...> ])
      true

      iex> %LedgerOperations{
      ...>    transaction_movements: [],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([
      ...>     %UnspentOutput{from: "@Charlie5", amount: 3_000_000_000, type: :UCO},
      ...>     %UnspentOutput{from: "@Bob4", amount: 10_000_000_000, type: {:NFT, "@BobNFT"}}
      ...> ])
      true
  """
  @spec sufficient_funds?(t(), list(UnspentOutput.t() | TransactionInput.t())) :: boolean()
  def sufficient_funds?(operations = %__MODULE__{}, inputs) when is_list(inputs) do
    %{uco: uco_balance, nft: nfts_received} = ledger_balances(inputs)
    %{uco: uco_to_spend, nft: nfts_to_spend} = total_to_spend(operations)
    uco_balance >= uco_to_spend and sufficient_nfts?(nfts_received, nfts_to_spend)
  end

  defp sufficient_nfts?(nfts_received = %{}, nft_to_spend = %{})
       when map_size(nfts_received) == 0 and map_size(nft_to_spend) > 0,
       do: false

  defp sufficient_nfts?(_nfts_received, nfts_to_spend) when map_size(nfts_to_spend) == 0, do: true

  defp sufficient_nfts?(nfts_received, nfts_to_spend) do
    Enum.all?(nfts_to_spend, fn {nft_address, amount_to_spend} ->
      case Map.get(nfts_received, nft_address) do
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

    # When using NFT unspent outputs are sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@CharlieNFT"}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Charlie1", amount: 200_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Bob3", amount: 1_200_000_000, type: {:NFT, "@CharlieNFT"}}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@CharlieNFT"}}
          ],
          fee: 40_000_000,
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 160_000_000, type: :UCO},
            %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: {:NFT, "@CharlieNFT"}}
          ]
      }

    #  When multiple NFT unspent outputs are sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@CharlieNFT"}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Charlie1", amount: 200_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Bob3", amount: 500_000_000, type: {:NFT, "@CharlieNFT"}},
      ...>    %UnspentOutput{from: "@Hugo5", amount: 700_000_000, type: {:NFT, "@CharlieNFT"}},
      ...>    %UnspentOutput{from: "@Tom1", amount: 700_000_000, type: {:NFT, "@CharlieNFT"}}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@CharlieNFT"}}
          ],
          fee: 40_000_000,
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 160_000_000, type: :UCO},
            %UnspentOutput{from: "@Alice2", amount: 900_000_000, type: {:NFT, "@CharlieNFT"}}
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
      %{uco: uco_balance, nft: nfts_received} = ledger_balances(inputs)
      %{uco: uco_to_spend, nft: nfts_to_spend} = total_to_spend(ops)

      new_unspent_outputs = [
        %UnspentOutput{from: change_address, amount: uco_balance - uco_to_spend, type: :UCO}
        | new_nft_unspent_outputs(nfts_received, nfts_to_spend, change_address)
      ]

      Map.update!(ops, :unspent_outputs, &(new_unspent_outputs ++ &1))
    else
      ops
    end
  end

  defp new_nft_unspent_outputs(nfts_received, nfts_to_spend, change_address) do
    Enum.reduce(nfts_to_spend, [], fn {nft_address, amount_to_spend}, acc ->
      case Map.get(nfts_received, nft_address) do
        nil ->
          acc

        recv_amount ->
          [
            %UnspentOutput{
              from: change_address,
              amount: recv_amount - amount_to_spend,
              type: {:NFT, nft_address}
            }
            | acc
          ]
      end
    end)
  end

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
      # Nb of transaction movements
      1,
      # Transaction movement recipient
      0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Transaction movement amount (1.2 UCO)
      0, 0, 0, 0, 6, 20, 101, 128,
      # Transaction movement type (UCO)
      0,
      # Nb of unspent outputs
      1,
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

    <<fee::64, length(transaction_movements)::8, bin_transaction_movements::binary,
      length(unspent_outputs)::8, bin_unspent_outputs::binary>>
  end

  @doc """
  Deserialize an encoded ledger operations

  ## Examples

      iex> <<0, 0, 0, 0, 0, 152, 150, 128, 1,
      ...> 0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      ...> 0, 0, 0, 0, 60, 203, 247, 0, 0,
      ...> 1, 0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237,
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
  def deserialize(<<fee::64, nb_transaction_movements::8, rest::bitstring>>) do
    {tx_movements, rest} = reduce_transaction_movements(rest, nb_transaction_movements, [])
    <<nb_unspent_outputs::8, rest::bitstring>> = rest
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
  Determines if the transaction movements are valid at a given time
  """
  @spec valid_transaction_movements?(t(), list(TransactionMovement.t()), DateTime.t()) ::
          boolean()
  def valid_transaction_movements?(
        %__MODULE__{fee: fee, transaction_movements: resolved_transaction_movements},
        tx_movements,
        timestamp = %DateTime{}
      ) do
    %__MODULE__{transaction_movements: expected_movements} =
      resolve_transaction_movements(%__MODULE__{fee: fee}, tx_movements, timestamp)

    Enum.all?(resolved_transaction_movements, &(&1 in expected_movements))
  end

  @doc """
  Resolve the transaction movements including the transaction's fee burning and retrieval of the last transaction addresses
  """
  @spec resolve_transaction_movements(t(), list(TransactionMovement.t()), DateTime.t()) :: t()
  def resolve_transaction_movements(
        ops = %__MODULE__{fee: fee},
        tx_movements,
        timestamp = %DateTime{}
      ) do
    burn_movement = %TransactionMovement{
      to: @burning_address,
      amount: fee,
      type: :UCO
    }

    resolved_movements =
      Task.Supervisor.async_stream_nolink(
        TaskSupervisor,
        tx_movements,
        fn mvt = %TransactionMovement{to: to} ->
          %{mvt | to: TransactionChain.resolve_last_address(to, timestamp)}
        end,
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.reduce([burn_movement], fn {:ok, res}, acc ->
        [res | acc]
      end)
      |> Enum.reverse()

    %{
      ops
      | transaction_movements: resolved_movements
    }
  end
end
