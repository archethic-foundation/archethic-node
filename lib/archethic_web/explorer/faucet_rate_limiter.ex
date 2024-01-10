defmodule ArchethicWeb.Explorer.FaucetRateLimiter do
  @moduledoc false

  use GenServer
  @vsn 1

  @faucet_rate_limit Application.compile_env!(:archethic, :faucet_rate_limit)
  @faucet_rate_limit_expiry Application.compile_env!(:archethic, :faucet_rate_limit_expiry)
  @block_period_expiry @faucet_rate_limit_expiry
  @clean_time @faucet_rate_limit_expiry

  @type address_status :: %{
          start_time: non_neg_integer(),
          last_time: non_neg_integer(),
          tx_count: non_neg_integer(),
          blocked?: boolean(),
          blocked_since: non_neg_integer()
        }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Client Call backs

  @doc """
  Register a faucet transaction address to monitor
  """
  @spec register(binary(), non_neg_integer()) :: :ok
  def register(address, start_time)
      when is_binary(address) and is_integer(start_time) do
    GenServer.cast(__MODULE__, {:register, address, start_time})
  end

  @doc false
  @spec clean_address(binary()) :: :ok
  def clean_address(address) do
    GenServer.call(__MODULE__, {:clean, address})
  end

  @spec get_address_block_status(binary()) :: address_status()
  def get_address_block_status(address)
      when is_binary(address) do
    GenServer.call(__MODULE__, {:block_status, address})
  end

  # Server Call backs
  @impl GenServer
  def init(_) do
    # Subscribe to PubSub
    schedule_clean()
    {:ok, %{}}
  end

  # Listen to event :new_transaction

  @impl GenServer
  def handle_call({:block_status, address}, _from, state) do
    address =
      case Archethic.fetch_genesis_address(address) do
        {:ok, genesis_address} ->
          genesis_address

        _ ->
          address
      end

    reply =
      if address_state = Map.get(state, address) do
        address_state
      else
        %{blocked?: false}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:clean, address}, _from, state) do
    {:reply, :ok, Map.delete(state, address)}
  end

  @impl GenServer
  def handle_cast({:register, address, start_time}, state) do
    initial_tx_setup = %{
      start_time: start_time,
      last_time: start_time,
      tx_count: 1,
      blocked?: false,
      blocked_since: nil
    }

    address =
      case Archethic.fetch_genesis_address(address) do
        {:ok, genesis_address} ->
          genesis_address

        _ ->
          address
      end

    updated_state =
      Map.update(state, address, initial_tx_setup, fn
        %{tx_count: tx_count} = transaction when tx_count + 1 == @faucet_rate_limit ->
          tx_count = transaction.tx_count + 1

          Process.send_after(self(), {:clean, address}, @block_period_expiry)

          %{
            transaction
            | blocked?: true,
              blocked_since: System.monotonic_time(),
              last_time: start_time,
              tx_count: tx_count + 1
          }

        %{tx_count: tx_count} = transaction ->
          transaction
          |> Map.put(:last_time, start_time)
          |> Map.put(:tx_count, tx_count + 1)
      end)

    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_info({:clean, address}, state) do
    {:noreply, Map.delete(state, address)}
  end

  @impl GenServer
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
