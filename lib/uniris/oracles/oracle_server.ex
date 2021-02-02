defmodule Uniris.Oracles.OracleCronServer do
  use GenServer

  # Public

  @spec start_link(mfa: mfa(), interval: pos_integer()) ::
          {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}
  def start_link([mfa: _, interval: _] = args) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec get_payload(pid()) :: {:ok, map()}
  def get_payload(pid), do: GenServer.call(pid, :get_payload)

  # Implementation

  @impl true
  def init(mfa: mfa, interval: interval) do
    state = %{
      mfa: mfa,
      interval: interval,
      subscribers: [],
      payload: nil
    }

    {:ok, state, {:continue, :prepare}}
  end

  @impl true
  def handle_continue(:prepare, %{mfa: {m, _, _}} = state) do
    {:ok, []} = m.start()

    Process.send_after(self(), :fetch, 0)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_payload, subscriber, %{payload: nil, subscribers: subscribers} = state) do
    {:noreply, %{state | subscribers: [subscriber | subscribers]}}
  end

  def handle_call(:get_payload, _, %{payload: payload} = state) do
    {:reply, payload, state}
  end

  @impl true
  def handle_info(:fetch, %{mfa: {m, f, a}} = state) do
    payload = apply(m, f, a)
    Process.send_after(self(), :send_tx, 0)

    Process.send_after(self(), :reschedule, 0)
    {:noreply, %{state | payload: payload}}
  end

  @impl true
  def handle_info(:reschedule, %{interval: interval, subscribers: []} = state) do
    Process.send_after(self(), :fetch, interval)
    {:noreply, state}
  end

  def handle_info(
        :reschedule,
        %{interval: interval, payload: payload, subscribers: [subscriber | subscribers]} = state
      ) do
    GenServer.reply(subscriber, {:ok, payload})

    Process.send_after(self(), :reschedule, interval)
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info(:send_tx, %{payload: payload} = state) do
    data = %Uniris.TransactionChain.TransactionData{content: payload}
    tx = Uniris.TransactionChain.Transaction.new(:oracle, data)
    :ok = Uniris.send_new_transaction(tx)

    {:noreply, state}
  end
end
