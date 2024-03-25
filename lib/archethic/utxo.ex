defmodule Archethic.UTXO do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.UTXO.DBLedger
  alias Archethic.UTXO.Loader
  alias Archethic.UTXO.MemoryLedger

  require Logger

  @type balance :: %{
          uco: amount :: pos_integer(),
          token: %{
            {address :: binary(), token_id :: non_neg_integer()} => amount :: pos_integer()
          }
        }

  @type load_opts :: [
          resolved_addresses: %{(address :: binary()) => genesis :: binary()},
          download_nodes: list(Node.t()),
          skip_consume_inputs?: boolean()
        ]

  @spec load_transaction(
          tx :: Transaction.t(),
          genesis_address :: binary(),
          opts :: load_opts()
        ) :: :ok
  def load_transaction(
        tx = %Transaction{validation_stamp: %ValidationStamp{protocol_version: protocol_version}},
        genesis_address,
        opts \\ []
      ) do
    resolved_addresses = Keyword.get(opts, :resolved_addresses, %{})
    download_nodes = Keyword.get(opts, :download_nodes, P2P.authorized_and_available_nodes())
    authorized_nodes = [P2P.get_node_info() | download_nodes] |> P2P.distinct_nodes()
    skip_consume_inputs? = Keyword.get(opts, :skip_consume_inputs?, false)

    node_public_key = Crypto.first_node_public_key()

    tx =
      if protocol_version <= 7,
        do: resolve_io_genesis(tx, authorized_nodes, resolved_addresses),
        else: tx

    # Ingest all the movements and recipients to fill up the UTXO list
    tx
    |> get_unspent_outputs_to_ingest(node_public_key, authorized_nodes)
    |> Enum.each(fn {to, utxos} -> Loader.add_utxos(utxos, to) end)

    # Consume the transaction to update the unspent outputs from the consumed inputs
    if not skip_consume_inputs? and
         Election.chain_storage_node?(genesis_address, node_public_key, authorized_nodes),
       do: Loader.consume_inputs(tx, genesis_address)

    Logger.info("Loaded into in memory UTXO tables",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )
  end

  defp get_unspent_outputs_to_ingest(
         %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{transaction_movements: []},
             recipients: []
           }
         },
         _,
         _
       ),
       do: %{}

  defp get_unspent_outputs_to_ingest(
         %Transaction{
           address: address,
           type: tx_type,
           validation_stamp: %ValidationStamp{
             protocol_version: protocol_version,
             timestamp: timestamp,
             ledger_operations: %LedgerOperations{transaction_movements: transaction_movements},
             recipients: recipients
           }
         },
         node_public_key,
         authorized_nodes
       ) do
    utxos_by_genesis =
      transaction_movements
      |> consolidate_movements(protocol_version, tx_type)
      |> Enum.reduce(%{}, fn %TransactionMovement{to: to, amount: amount, type: type}, acc ->
        utxo = %UnspentOutput{from: address, amount: amount, timestamp: timestamp, type: type}

        with true <- Election.chain_storage_node?(to, node_public_key, authorized_nodes),
             false <- utxo_consumed?(to, utxo) do
          versioned_utxo = VersionedUnspentOutput.wrap_unspent_output(utxo, protocol_version)
          Map.update(acc, to, [versioned_utxo], &[versioned_utxo | &1])
        else
          _ -> acc
        end
      end)

    Enum.reduce(recipients, utxos_by_genesis, fn recipient, acc ->
      utxo = %UnspentOutput{from: address, type: :call, timestamp: timestamp}

      with true <- Election.chain_storage_node?(recipient, node_public_key, authorized_nodes),
           false <- utxo_consumed?(recipient, utxo) do
        versioned_utxo = VersionedUnspentOutput.wrap_unspent_output(utxo, protocol_version)
        Map.update(acc, recipient, [versioned_utxo], &[versioned_utxo | &1])
      else
        _ -> acc
      end
    end)
  end

  defp consolidate_movements([], _, _), do: []

  defp consolidate_movements(transaction_movements, protocol_version, tx_type)
       when protocol_version < 5 do
    transaction_movements
    |> Enum.map(fn movement -> TransactionMovement.maybe_convert_reward(movement, tx_type) end)
    |> TransactionMovement.aggregate()
  end

  defp consolidate_movements(transaction_movements, _protocol_version, _tx_type),
    do: transaction_movements

  defp resolve_io_genesis(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{transaction_movements: movements},
             recipients: recipients
           }
         },
         authorized_nodes,
         resolved_addresses
       )
       when length(movements) + length(recipients) > 0 and map_size(resolved_addresses) == 0 do
    resolved_addresses =
      movements
      |> Enum.map(& &1.to)
      |> Enum.concat(recipients)
      |> Task.async_stream(
        fn address ->
          nodes = Election.chain_storage_nodes(address, authorized_nodes)

          case TransactionChain.fetch_genesis_address(address, nodes) do
            {:ok, genesis} -> {address, genesis}
            _ -> {address, address}
          end
        end,
        on_timeout: :kill_task,
        max_concurrency: length(movements) + length(recipients)
      )
      |> Enum.map(fn {:ok, addresses} -> addresses end)
      |> Map.new()

    update_tx_io_addresses(tx, resolved_addresses)
  end

  defp resolve_io_genesis(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{transaction_movements: movements},
             recipients: recipients
           }
         },
         _authorized_nodes,
         resolved_addresses
       )
       when length(movements) + length(recipients) > 0,
       do: update_tx_io_addresses(tx, resolved_addresses)

  defp resolve_io_genesis(tx, _, _), do: tx

  defp update_tx_io_addresses(tx, resolved_addresses) do
    tx
    |> update_in(
      [
        Access.key!(:validation_stamp),
        Access.key!(:ledger_operations),
        Access.key!(:transaction_movements)
      ],
      fn movements ->
        Enum.map(movements, &%TransactionMovement{&1 | to: Map.fetch!(resolved_addresses, &1.to)})
      end
    )
    |> update_in(
      [
        Access.key!(:validation_stamp),
        Access.key!(:recipients)
      ],
      fn recipients -> Enum.map(recipients, &Map.fetch!(resolved_addresses, &1)) end
    )
  end

  defp utxo_consumed?(genesis_address, utxo = %UnspentOutput{timestamp: utxo_timestamp}) do
    {_, last_timestamp} = TransactionChain.get_last_address(genesis_address)

    if DateTime.compare(last_timestamp, utxo_timestamp) == :gt do
      genesis_address
      |> TransactionChain.list_chain_addresses()
      |> Stream.filter(fn {_, timestamp} -> DateTime.compare(timestamp, utxo_timestamp) == :gt end)
      |> Stream.map(fn {address, _} -> get_transaction_fields(address) end)
      |> Enum.any?(fn
        {:ok, {protocol_version, consumed_inputs, unspent_outputs}} ->
          if protocol_version < 7,
            do: not Enum.member?(unspent_outputs, utxo),
            else:
              consumed_inputs
              |> VersionedUnspentOutput.unwrap_unspent_outputs()
              |> Enum.member?(utxo)

        :error ->
          false
      end)
    else
      false
    end
  end

  defp get_transaction_fields(address) do
    fields = [
      validation_stamp: [
        :protocol_version,
        ledger_operations: [:consumed_inputs, :unspent_outputs]
      ]
    ]

    case TransactionChain.get_transaction(address, fields) do
      {:ok,
       %Transaction{
         validation_stamp: %ValidationStamp{
           protocol_version: protocol_version,
           ledger_operations: %LedgerOperations{
             consumed_inputs: consumed_inputs,
             unspent_outputs: unspent_outputs
           }
         }
       }} ->
        {:ok, {protocol_version, consumed_inputs, unspent_outputs}}

      {:error, _} ->
        :error
    end
  end

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec stream_unspent_outputs(binary()) :: list(VersionedUnspentOutput.t())
  def stream_unspent_outputs(address) do
    case MemoryLedger.get_unspent_outputs(address) do
      [] ->
        DBLedger.stream(address)

      memory_utxos ->
        memory_utxos
    end
  end

  @doc """
  Returns the balance for an address using the unspent outputs

  ## Examples

      iex> [
      ...>   %UnspentOutput{ from: "@Alice10", type: :UCO, amount: 100_000_000},
      ...>   %UnspentOutput{ from: "@Bob5", type: {:token, "MyToken", 0}, amount: 300_000_000},
      ...>   %UnspentOutput{ from: "@Charlie5", type: :call},
      ...>   %UnspentOutput{ from: "@Tom5", type: :state},
      ...> ]
      ...> |> UTXO.get_balance()
      %{
         uco: 100_000_000,
         token: %{
           {"MyToken", 0} => 300_000_000
         }
      }
  """
  @spec get_balance(Enumerable.t() | list(UnspentOutput.t())) :: balance()
  def get_balance(unspent_outputs) do
    Enum.reduce(unspent_outputs, %{uco: 0, token: %{}}, fn
      %UnspentOutput{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %UnspentOutput{type: {:token, token_address, token_id}, amount: amount}, acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))

      _, acc ->
        acc
    end)
  end
end
