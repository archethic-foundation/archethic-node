defmodule ArchEthicWeb.FaucetRateLimiter do
  @moduledoc false

  use GenServer

  @faucet_rate_limit Application.compile_env!(:archethic, :faucet_rate_limit)
  @faucet_rate_limit_expiry Application.compile_env!(:archethic, :faucet_rate_limit_expiry)
  @archive_period_expiry @faucet_rate_limit_expiry
  @clean_time @faucet_rate_limit_expiry

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a faucet transaction address to monitor
  """
  @spec register(binary(), non_neg_integer()) :: :ok

  ## Client Call backs
  def register(address, start_time)
      when is_binary(address) and is_integer(start_time) do
    GenServer.cast(__MODULE__, {:register, address, start_time})
  end

  def reset() do
    GenServer.call(__MODULE__, :reset)
  end

  def clean_address(address) do
    GenServer.call(__MODULE__, {:clean, address})
  end

  def get_address_archive_status(address)
      when is_binary(address) do
    GenServer.call(__MODULE__, {:archive_status, address})
  end

  # Server Call backs
  def init(_) do
    schedule_clean()
    {:ok, %{}}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{}}
  end

  def handle_call({:archive_status, address}, _from, state) do
    reply =
      if address_state = Map.get(state, address) do
        address_state
      else
        %{archived?: false}
      end

    {:reply, reply, state}
  end

  def handle_call({:clean, address}, _from, state) do
    {:reply, :ok, Map.delete(state, address)}
  end

  def handle_cast({:register, address, start_time}, state) do
    transaction = Map.get(state, address)

    transaction_info =
      if transaction do
        tx_count = transaction.tx_count + 1

        if tx_count == @faucet_rate_limit do
          GenServer.cast(__MODULE__, {:archive, address})
          Process.send_after(self(), {:clean, address}, @archive_period_expiry)
        end

        transaction
        |> Map.put(:last_time, start_time)
        |> Map.put(:tx_count, tx_count)
      else
        %{
          start_time: start_time,
          last_time: start_time,
          tx_count: 1,
          archived?: false,
          archived_since: nil
        }
      end

    {:noreply, Map.put(state, address, transaction_info)}
  end

  def handle_cast({:archive, address}, state) do
    transaction = Map.get(state, address)
    transaction = %{transaction | archived?: true, archived_since: System.monotonic_time()}
    new_state = Map.put(state, address, transaction)
    {:noreply, new_state}
  end

  def handle_info({:clean, address}, state) do
    {:noreply, Map.delete(state, address)}
  end

  def handle_info(:clean, state) do
    schedule_clean()
    now = System.monotonic_time()

    new_state =
      Enum.filter(state, fn
        {_address, %{last_time: start_time}} ->
          millisecond_elapsed = System.convert_time_unit(now - start_time, :native, :millisecond)
          millisecond_elapsed <= @archive_period_expiry
      end)
      |> Enum.into(%{})

    {:noreply, new_state}
  end

  defp schedule_clean() do
    Process.send_after(self(), :clean, @clean_time)
  end
end
