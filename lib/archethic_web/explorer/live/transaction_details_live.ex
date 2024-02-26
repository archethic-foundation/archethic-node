defmodule ArchethicWeb.Explorer.TransactionDetailsLive do
  @moduledoc false
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.PubSub
  alias Archethic.Reward
  alias Archethic.TaskSupervisor
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer
  alias Archethic.TransactionChain.TransactionInput
  alias ArchethicWeb.WebUtils
  alias ArchethicWeb.Explorer.Components.InputsList
  alias ArchethicWeb.Explorer.Components.UnspentOutputList
  alias ArchethicWeb.Explorer.Components.Amount
  import ArchethicWeb.Explorer.ExplorerView

  def mount(params, _session, socket) do
    uco_price_now = DateTime.utc_now() |> OracleChain.get_uco_price()
    debug? = Map.has_key?(params, "debug")

    {:ok,
     assign(socket, %{
       exists: false,
       previous_address: nil,
       transaction: nil,
       inputs: [],
       calls: [],
       uco_price_now: uco_price_now,
       linked_movements: [],
       debug?: debug?
     })}
  end

  def handle_params(%{"address" => address}, _uri, socket) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(addr) do
      case Archethic.search_transaction(addr) do
        {:ok, tx} ->
          {:noreply, handle_transaction(socket, tx)}

        {:error, :transaction_not_exists} ->
          PubSub.register_to_new_transaction_by_address(addr)
          {:noreply, handle_not_existing_transaction(socket, addr)}

        {:error, :invalid_transaction} ->
          {:noreply, handle_invalid_transaction(socket, addr)}
      end
    else
      _ ->
        {:noreply, handle_invalid_address(socket, address)}
    end
  end

  def handle_info({:new_transaction, address}, socket) do
    {:ok, tx} = Archethic.search_transaction(address)

    new_socket =
      socket
      |> assign(:ko?, false)
      |> handle_transaction(tx)

    {:noreply, new_socket}
  end

  def handle_info({:async_assign, assigns}, socket) do
    {:noreply, assign(socket, assigns)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp handle_transaction(
         socket = %{assigns: %{debug?: debug?}},
         tx = %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{timestamp: timestamp}
         }
       ) do
    previous_address = Transaction.previous_address(tx)

    uco_price_at_time = OracleChain.get_uco_price(timestamp)

    async_assign_resolved_movements(tx)
    async_assign_inputs_and_token_properties(tx, debug?)

    socket
    |> assign(:transaction, tx)
    |> assign(:previous_address, previous_address)
    |> assign(:address, address)
    |> assign(:uco_price_at_time, uco_price_at_time)
    |> assign(:inputs, [])
    |> assign(:calls, [])
    |> assign(:token_properties, %{})
    |> assign(:linked_movements, [])
  end

  defp async_assign_resolved_movements(%Transaction{
         address: address,
         type: type,
         data: %TransactionData{
           content: content,
           ledger: %Ledger{
             token: %TokenLedger{transfers: token_transfers},
             uco: %UCOLedger{transfers: uco_transfers}
           }
         },
         validation_stamp: %ValidationStamp{
           ledger_operations: %LedgerOperations{transaction_movements: movements},
           protocol_version: protocol_version
         }
       }) do
    me = self()

    Task.Supervisor.async_nolink(TaskSupervisor, fn ->
      transfers_from_content =
        if type in [:mint_rewards, :token],
          do: get_transfers_from_token_tx(address, content),
          else: []

      transfers = uco_transfers ++ token_transfers ++ transfers_from_content

      transfers_to_resolve = if protocol_version <= 7, do: transfers ++ movements, else: transfers

      linked_movements =
        transfers_to_resolve
        |> Enum.map(& &1.to)
        |> Enum.uniq()
        |> resolve_genesis_addresses()
        |> link_movement_to_transfers(transfers, movements, protocol_version)

      send(me, {:async_assign, [linked_movements: linked_movements]})
    end)
  end

  defp get_transfers_from_token_tx(address, content) do
    address
    |> Transaction.get_movements_from_token_transaction(content)
    |> Enum.map(fn %TransactionMovement{
                     to: to,
                     type: {:token, token_address, token_id},
                     amount: amount
                   } ->
      %TokenTransfer{to: to, token_address: token_address, token_id: token_id, amount: amount}
    end)
  end

  defp resolve_genesis_addresses(addresses) do
    Task.Supervisor.async_stream_nolink(TaskSupervisor, addresses, fn address ->
      case Archethic.fetch_genesis_address(address) do
        {:ok, genesis} -> {address, genesis}
        _ -> {address, address}
      end
    end)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, resolution} -> resolution end)
    |> Map.new()
  end

  defp link_movement_to_transfers(resolved_genesis, transfers, movements, protocol_version) do
    Enum.map(movements, &find_transfers(&1, resolved_genesis, transfers, protocol_version))
  end

  defp find_transfers(
         movement = %TransactionMovement{to: movement_recipient, type: :UCO},
         resolved_genesis,
         transfers,
         protocol_version
       ) do
    movement_genesis = Map.get(resolved_genesis, movement_recipient, movement_recipient)

    filtered_transfers =
      Enum.filter(transfers, fn
        %UCOTransfer{to: transfer_recipient} ->
          movement_genesis == Map.get(resolved_genesis, transfer_recipient)

        %TokenTransfer{to: transfer_recipient, token_address: token_address} ->
          # Before protocol version 5, rewards where not converted to UCO movement
          Reward.is_reward_token?(token_address) and protocol_version >= 5 and
            movement_genesis == Map.get(resolved_genesis, transfer_recipient)
      end)

    {movement, filtered_transfers}
  end

  defp find_transfers(
         movement = %TransactionMovement{
           to: movement_recipient,
           type: {:token, token_address, token_id}
         },
         resolved_genesis,
         transfers,
         _protocol_version
       ) do
    movement_genesis = Map.get(resolved_genesis, movement_recipient, movement_recipient)

    filtered_transfers =
      Enum.filter(transfers, fn
        %TokenTransfer{to: transfer_recipient, token_address: ^token_address, token_id: ^token_id} ->
          movement_genesis == Map.get(resolved_genesis, transfer_recipient)

        _ ->
          false
      end)

    {movement, filtered_transfers}
  end

  defp async_assign_inputs_and_token_properties(
         %Transaction{
           address: address,
           data: %TransactionData{
             ledger: %Ledger{token: %TokenLedger{transfers: token_transfers}}
           },
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{
               transaction_movements: transaction_movements,
               unspent_outputs: unspent_outputs
             }
           }
         },
         debug?
       ) do
    me = self()

    Task.Supervisor.async_nolink(
      TaskSupervisor,
      fn ->
        inputs = get_transaction_inputs(address, debug?)

        assigns =
          if debug? do
            [inputs: inputs]
          else
            ledger_inputs = Enum.reject(inputs, &(&1.type == :call))
            contract_inputs = Enum.filter(inputs, &(&1.type == :call))

            [inputs: ledger_inputs, calls: contract_inputs]
          end

        send(me, {:async_assign, assigns})

        get_token_addresses([], Keyword.get(assigns, :inputs))
        |> get_token_addresses(unspent_outputs)
        |> get_token_addresses(transaction_movements)
        |> get_token_addresses(token_transfers)
        |> Enum.uniq()
        |> async_assign_token_properties(me)
      end,
      timeout: 20_000
    )
  end

  defp async_assign_inputs_and_token_properties(address, debug?) do
    me = self()

    Task.Supervisor.async_nolink(
      TaskSupervisor,
      fn ->
        inputs = get_transaction_inputs(address, debug?)

        assigns =
          if debug? do
            [inputs: inputs]
          else
            ledger_inputs = Enum.reject(inputs, &(&1.type == :call))
            contract_inputs = Enum.filter(inputs, &(&1.type == :call))

            [inputs: ledger_inputs, calls: contract_inputs]
          end

        send(me, {:async_assign, assigns})

        get_token_addresses([], Keyword.get(assigns, :inputs))
        |> Enum.uniq()
        |> async_assign_token_properties(me)
      end,
      timeout: 20_000
    )
  end

  defp get_transaction_inputs(address, _debug? = false),
    do: Archethic.get_transaction_inputs(address)

  defp get_transaction_inputs(address, _debug? = true) do
    case Archethic.fetch_genesis_address(address) do
      {:ok, genesis_address} -> Archethic.get_unspent_outputs(genesis_address)
      _ -> []
    end
  end

  defp async_assign_token_properties(token_addresses, pid) do
    Task.Supervisor.async_nolink(
      TaskSupervisor,
      fn ->
        assigns = [token_properties: get_token_properties(token_addresses)]

        send(pid, {:async_assign, assigns})
      end,
      timeout: 20_000
    )
  end

  defp handle_not_existing_transaction(socket = %{assigns: %{debug?: debug?}}, address) do
    async_assign_inputs_and_token_properties(address, debug?)

    socket
    |> assign(:address, address)
    |> assign(:inputs, [])
    |> assign(:calls, [])
    |> assign(:error, :not_exists)
    |> assign(:token_properties, %{})
  end

  defp get_token_addresses(acc, [%TransactionMovement{type: {:token, token_address, _}} | rest]) do
    get_token_addresses([token_address | acc], rest)
  end

  defp get_token_addresses(acc, [%TransactionInput{type: {:token, token_address, _}} | rest]) do
    get_token_addresses([token_address | acc], rest)
  end

  defp get_token_addresses(acc, [%UnspentOutput{type: {:token, token_address, _}} | rest]) do
    get_token_addresses([token_address | acc], rest)
  end

  defp get_token_addresses(acc, [%TokenTransfer{token_address: token_address} | rest]) do
    get_token_addresses([token_address | acc], rest)
  end

  defp get_token_addresses(acc, [_ | rest]) do
    get_token_addresses(acc, rest)
  end

  defp get_token_addresses(acc, []), do: acc

  defp get_token_properties(token_addresses) do
    Task.async_stream(token_addresses, fn token_address ->
      case Archethic.search_transaction(token_address) do
        {:ok, %Transaction{data: %TransactionData{content: content}, type: type}}
        when type in [:token, :mint_rewards] ->
          {token_address, content}

        _ ->
          :error
      end
    end)
    |> Enum.reduce(%{}, fn
      {:ok, {token_address, content}}, acc ->
        case Jason.decode(content) do
          {:ok, map} ->
            properties = %{
              decimals: Map.get(map, "decimals", 8),
              symbol: Map.get(map, "symbol", Map.get(map, "name"))
            }

            Map.put(acc, token_address, properties)

          _ ->
            acc
        end

      _, acc ->
        acc
    end)
  end

  defp handle_invalid_address(socket, address) do
    socket
    |> assign(:address, address)
    |> assign(:error, :invalid_address)
  end

  defp handle_invalid_transaction(socket, address) do
    socket
    |> assign(:address, address)
    |> assign(:ko?, true)
  end

  def print_state(%UnspentOutput{encoded_payload: encoded_state}) do
    encoded_state |> State.deserialize() |> elem(0) |> Jason.encode!(pretty: true)
  end

  # loop through the inputs to detect if a UTXO is spent or not
  def utxo_spent?(utxo, inputs) do
    case Enum.find(inputs, &similar?(&1, utxo)) do
      nil -> true
      input -> input.spent?
    end
  end

  def filter_inputs(inputs, utxos) do
    Enum.reject(inputs, fn input ->
      Enum.any?(utxos, &similar?(input, &1))
    end)
  end

  defp similar?(
         %TransactionInput{
           type: in_type,
           from: in_from,
           amount: in_amount,
           timestamp: in_timestamp
         },
         %UnspentOutput{
           type: out_type,
           from: out_from,
           amount: out_amount,
           timestamp: out_timestamp
         }
       ) do
    # sometimes inputs' dates are rounded to second but not always
    # this means we need to truncate to compare
    in_type == out_type &&
      in_from == out_from &&
      in_amount == out_amount &&
      DateTime.truncate(in_timestamp, :second) == DateTime.truncate(out_timestamp, :second)
  end

  defp similar?(_, _) do
    false
  end
end
