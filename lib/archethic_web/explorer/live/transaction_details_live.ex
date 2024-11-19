defmodule ArchethicWeb.Explorer.TransactionDetailsLive do
  @moduledoc false
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.PubSub
  alias Archethic.P2P
  alias Archethic.Reward

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

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

  def mount(_params, _session, socket) do
    uco_price_now = DateTime.utc_now() |> OracleChain.get_uco_price()

    {:ok,
     assign(socket, %{
       exists: false,
       previous_address: nil,
       transaction: nil,
       inputs: [],
       uco_price_now: uco_price_now,
       linked_movements: []
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
         socket,
         tx = %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{timestamp: timestamp},
           proof_of_validation: proof
         }
       ) do
    uco_price_at_time = OracleChain.get_uco_price(timestamp)

    async_assign_resolved_movements(tx)
    async_assign_inputs_and_token_properties(tx)

    previous_address =
      if TransactionChain.first_transaction?(tx), do: nil, else: Transaction.previous_address(tx)

    proof_of_validation =
      if proof != nil do
        timestamp
        |> P2P.authorized_and_available_nodes()
        |> ProofOfValidation.get_election(address)
        |> ProofOfValidation.to_map(proof)
      end

    socket
    |> assign(:transaction, tx)
    |> assign(:proof_of_validation, proof_of_validation)
    |> assign(:previous_address, previous_address)
    |> assign(:address, address)
    |> assign(:uco_price_at_time, uco_price_at_time)
    |> assign(:inputs, [])
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

    Task.Supervisor.async_nolink(Archethic.task_supervisors(), fn ->
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
    Task.Supervisor.async_stream_nolink(Archethic.task_supervisors(), addresses, fn address ->
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
         tx = %Transaction{
           data: %TransactionData{
             ledger: %Ledger{token: %TokenLedger{transfers: token_transfers}}
           },
           validation_stamp: %ValidationStamp{
             protocol_version: protocol_version,
             ledger_operations: %LedgerOperations{
               transaction_movements: transaction_movements,
               unspent_outputs: unspent_outputs,
               consumed_inputs: consumed_inputs
             }
           }
         }
       ) do
    me = self()

    Task.Supervisor.async_nolink(
      Archethic.task_supervisors(),
      fn ->
        inputs =
          tx
          |> Transaction.previous_address()
          |> Archethic.get_transaction_inputs()
          # We flag as consumed the inputs really used in the transaction
          |> Enum.map(fn
            input when protocol_version < 7 ->
              Map.put(input, :consumed?, true)

            input ->
              Map.put(
                input,
                :consumed?,
                Enum.any?(consumed_inputs, &similar?(input, &1.unspent_output))
              )
          end)

        send(me, {:async_assign, inputs: inputs})

        get_token_addresses([], inputs)
        |> get_token_addresses(unspent_outputs)
        |> get_token_addresses(transaction_movements)
        |> get_token_addresses(token_transfers)
        |> Enum.uniq()
        |> async_assign_token_properties(me)
      end,
      timeout: 20_000
    )
  end

  defp async_assign_token_properties(token_addresses, pid) do
    Task.Supervisor.async_nolink(
      Archethic.task_supervisors(),
      fn ->
        assigns = [token_properties: WebUtils.get_token_properties(token_addresses)]

        send(pid, {:async_assign, assigns})
      end,
      timeout: 20_000
    )
  end

  defp handle_not_existing_transaction(socket, address) do
    socket
    |> assign(:address, address)
    |> assign(:inputs, [])
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

  defp handle_invalid_address(socket, address) do
    socket
    |> assign(:address, address)
    |> assign(:error, :invalid_address)
  end

  def print_state(%UnspentOutput{encoded_payload: encoded_state}, protocol_version) do
    encoded_state |> State.deserialize(protocol_version) |> elem(0) |> State.format()
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
