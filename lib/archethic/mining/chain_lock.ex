defmodule Archethic.Mining.ChainLock do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.PubSub

  use GenServer
  require Logger

  @vsn 1

  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @spec lock(address :: Crypto.prepended_hash(), tx_hash :: binary()) ::
          :ok | {:error, :already_locked}
  def lock(address, tx_hash) do
    address |> via_tuple() |> GenServer.call({:lock, address, tx_hash})
  end

  @spec unlock(address :: Crypto.prepended_hash()) :: :ok
  def unlock(address) do
    address |> via_tuple() |> GenServer.cast({:unlock, address})
  end

  defp via_tuple(address) do
    {:via, PartitionSupervisor, {ChainLockSupervisor, address}}
  end

  def init(args) do
    timeout = Keyword.fetch!(args, :mining_timeout)
    {:ok, %{timeout: timeout, addresses_locked: Map.new()}}
  end

  def handle_call(
        {:lock, address, tx_hash},
        _from,
        state = %{timeout: timeout, addresses_locked: addresses_locked}
      ) do
    case Map.get(addresses_locked, address) do
      nil ->
        Logger.info("Lock transaction chain", transaction_address: Base.encode16(address))
        PubSub.register_to_new_transaction_by_address(address)
        timer = Process.send_after(self(), {:unlock, address}, timeout)

        new_state = Map.update!(state, :addresses_locked, &Map.put(&1, address, {tx_hash, timer}))

        {:reply, :ok, new_state}

      {hash, _timer} when hash == tx_hash ->
        {:reply, :ok, state}

      _ ->
        Logger.debug("Received lock with different transaction hash",
          transaction_address: Base.encode16(address)
        )

        {:reply, {:error, :already_locked}, state}
    end
  end

  # Unlock from message UnlockChain
  def handle_cast({:unlock, address}, state) do
    new_state = Map.update!(state, :addresses_locked, &unlock_address(&1, address))
    {:noreply, new_state}
  end

  # Unlock from self unlock after timeout
  def handle_info({:unlock, address}, state) do
    new_state = Map.update!(state, :addresses_locked, &unlock_address(&1, address))
    {:noreply, new_state}
  end

  # Unlock from transaction being replicated
  def handle_info({:new_transaction, address}, state) do
    new_state = Map.update!(state, :addresses_locked, &unlock_address(&1, address))
    {:noreply, new_state}
  end

  # Unlock from transaction being replicated
  def handle_info({:new_transaction, address, _type, _timestamp}, state) do
    new_state = Map.update!(state, :addresses_locked, &unlock_address(&1, address))
    {:noreply, new_state}
  end

  defp unlock_address(addresses_locked, address) do
    PubSub.unregister_to_new_transaction_by_address(address)

    case Map.pop(addresses_locked, address) do
      {nil, _} ->
        addresses_locked

      {{_hash, timer}, new_addresses_locked} ->
        Process.cancel_timer(timer)
        Logger.debug("Unlock transaction chain", transaction_address: Base.encode16(address))
        new_addresses_locked
    end
  end
end
