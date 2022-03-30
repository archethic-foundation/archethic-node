defmodule ArchEthicWeb.FaucetRateLimiter do
  @moduledoc false

  use GenServer

  @faucet_rate_limit Application.compile_env!(:archethic, :faucet_rate_limit)
  @faucet_rate_limit_expiry Application.compile_env!(:archethic, :faucet_rate_limit_expiry)
  @block_period_expiry @faucet_rate_limit_expiry
  @clean_time @faucet_rate_limit_expiry

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a faucet transaction address to monitor
  """
  @spec register(binary(), non_neg_integer()) :: :ok

  def register(tx_address, start_time)
      when is_binary(tx_address) and is_integer(start_time) do
    GenServer.cast(__MODULE__, {:register, tx_address, start_time})
  end

  def init(_) do
    schedule_clean()
    {:ok, %{}}
  end

  def handle_cast({:register, tx_address, start_time}, state) do
    transaction = Map.get(state, tx_address)

    transaction_info =
      if transaction do
        tx_count = transaction.tx_count + 1

        if tx_count == @faucet_rate_limit do
          GenServer.cast(__MODULE__, {:block, tx_address})
          Process.send_after(self(), {:clean, tx_address}, @block_period_expiry)
        end

        transaction
        |> Map.put(:last_time, start_time)
        |> Map.put(:tx_count, tx_count)
      else
        %{
          start_time: start_time,
          last_time: start_time,
          transactions_count: 1,
          blocked?: false
        }
      end

    {:noreply, Map.put(state, tx_address, transaction_info)}
  end

  def handle_cast({:block, tx_address}, state) do
    transaction = Map.get(state, tx_address)
    transaction = %{transaction | blocked?: true}
    new_state = Map.put(state, tx_address, transaction)
    {:noreply, new_state}
  end

  def handle_info({:clean, tx_address}, state) do
    {:noreply, Map.delete(state, tx_address)}
  end

  def handle_info(:clean, state) do
    schedule_clean()
    now = System.monotonic_time()

    new_state =
      Enum.filter(state, fn
        {_address, %{last_time: start_time}} ->
          millisecond_elapsed = System.convert_time_unit(now - start_time, :native, :millisecond)
          millisecond_elapsed <= @block_period_expiry
      end)
      |> Enum.into(%{})

    {:noreply, new_state}
  end

  defp schedule_clean() do
    Process.send_after(self(), :clean, @clean_time)
  end
end
