defmodule ArchethicWeb.Explorer.TransactionDetailsLive do
  @moduledoc false
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.PubSub
  alias Archethic.TaskSupervisor
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionInput
  alias ArchethicWeb.WebUtils
  alias ArchethicWeb.Explorer.Components.InputsList
  import ArchethicWeb.Explorer.ExplorerView

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, %{
       exists: false,
       previous_address: nil,
       transaction: nil,
       inputs: [],
       calls: []
     })}
  end

  def handle_params(opts = %{"address" => address}, _uri, socket) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(addr) do
      case get_transaction(addr, opts) do
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
    {:ok, tx} = get_transaction(address, %{})

    new_socket =
      socket
      |> assign(:ko?, false)
      |> handle_transaction(tx)

    {:noreply, new_socket}
  end

  def handle_info(
        {:async_assign_inputs,
         [
           assigns: assigns,
           transaction_movements: transaction_movements,
           token_transfers: token_transfers
         ]},
        socket
      ) do
    async_assign_token_properties(assigns[:inputs], transaction_movements, token_transfers)

    {:noreply, assign(socket, assigns)}
  end

  def handle_info({:async_assign_token_properties, assigns}, socket) do
    {:noreply, assign(socket, assigns)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp get_transaction(address, %{"address" => "true"}) do
    Archethic.get_last_transaction(address)
  end

  defp get_transaction(address, _opts = %{}) do
    Archethic.search_transaction(address)
  end

  defp handle_transaction(
         socket,
         tx = %Transaction{
           address: address,
           data: %TransactionData{
             ledger: %Ledger{token: %TokenLedger{transfers: token_transfers}}
           },
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{transaction_movements: transaction_movements}
           }
         }
       ) do
    previous_address = Transaction.previous_address(tx)

    uco_price_at_time = tx.validation_stamp.timestamp |> OracleChain.get_uco_price()
    uco_price_now = DateTime.utc_now() |> OracleChain.get_uco_price()

    async_assign_inputs_and_token_properties(address, transaction_movements, token_transfers)

    socket
    |> assign(:transaction, tx)
    |> assign(:previous_address, previous_address)
    |> assign(:address, address)
    |> assign(:uco_price_at_time, uco_price_at_time)
    |> assign(:uco_price_now, uco_price_now)
    |> assign(:inputs, [])
    |> assign(:calls, [])
    |> assign(:token_properties, %{})
  end

  defp async_assign_inputs_and_token_properties(address, transaction_movements, token_transfers) do
    me = self()

    Task.Supervisor.async_nolink(
      TaskSupervisor,
      fn ->
        inputs = Archethic.get_transaction_inputs(address)
        ledger_inputs = Enum.reject(inputs, &(&1.type == :call))
        contract_inputs = Enum.filter(inputs, &(&1.type == :call))

        assigns = [
          inputs: ledger_inputs,
          calls: contract_inputs
        ]

        send(
          me,
          {:async_assign_inputs,
           [
             assigns: assigns,
             transaction_movements: transaction_movements,
             token_transfers: token_transfers
           ]}
        )
      end,
      timeout: 20_000
    )
  end

  defp async_assign_token_properties(ledger_inputs, transaction_movements, token_transfers) do
    me = self()

    Task.Supervisor.async_nolink(
      TaskSupervisor,
      fn ->
        token_properties =
          get_token_addresses([], ledger_inputs)
          |> get_token_addresses(transaction_movements)
          |> get_token_addresses(token_transfers)
          |> Enum.uniq()
          |> get_token_properties()

        assigns = [
          token_properties: token_properties
        ]

        send(
          me,
          {:async_assign_token_properties, assigns}
        )
      end,
      timeout: 20_000
    )
  end

  defp handle_not_existing_transaction(socket, address) do
    inputs = Archethic.get_transaction_inputs(address)
    ledger_inputs = Enum.reject(inputs, &(&1.type == :call))
    contract_inputs = Enum.filter(inputs, &(&1.type == :call))

    token_properties =
      get_token_addresses([], ledger_inputs)
      |> Enum.uniq()
      |> get_token_properties()

    socket
    |> assign(:address, address)
    |> assign(:inputs, ledger_inputs)
    |> assign(:calls, contract_inputs)
    |> assign(:error, :not_exists)
    |> assign(:token_properties, token_properties)
  end

  defp get_token_addresses(acc, [%TransactionMovement{type: {:token, token_address, _}} | rest]) do
    get_token_addresses([token_address | acc], rest)
  end

  defp get_token_addresses(acc, [%TransactionInput{type: {:token, token_address, _}} | rest]) do
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
              symbol: Map.get(map, "symbol")
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
end
