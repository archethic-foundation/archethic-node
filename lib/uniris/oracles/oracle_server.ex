defmodule Uniris.Oracles.OracleCronServer do
  @moduledoc false

  use GenServer

  alias Uniris.TransactionChain.{
    Transaction,
    TransactionData
  }

  # Public

  @spec start_link(mfa: mfa(), interval: pos_integer()) ::
          {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}
  def start_link(args = [mfa: _, interval: _]) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec get_payload(pid()) :: {:ok, map()}
  def get_payload(pid), do: GenServer.call(pid, :get_payload)

  # Implementation

  @impl GenServer
  def init(mfa: mfa, interval: interval) do
    state = %{
      mfa: mfa,
      interval: interval,
      subscribers: [],
      payload: nil
    }

    {:ok, state, {:continue, :prepare}}
  end

  @impl GenServer
  def handle_continue(:prepare, %{mfa: state = {m, _, _}}) do
    {:ok, []} = m.start()

    Process.send_after(self(), :fetch, 0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_payload, subscriber, state = %{payload: nil, subscribers: subscribers}) do
    {:noreply, %{state | subscribers: [subscriber | subscribers]}}
  end

  def handle_call(:get_payload, _, state = %{payload: payload}) do
    {:reply, payload, state}
  end

  @impl GenServer
  def handle_info(:fetch, state = %{mfa: {m, f, a}}) do
    payload = apply(m, f, a)
    Process.send_after(self(), :send_tx, 0)

    Process.send_after(self(), :reschedule, 0)
    {:noreply, %{state | payload: payload}}
  end

  def handle_info(:reschedule, state = %{interval: interval, subscribers: []}) do
    Process.send_after(self(), :fetch, interval)
    {:noreply, state}
  end

  def handle_info(
        :reschedule,
        state = %{interval: interval, payload: payload, subscribers: [subscriber | subscribers]}
      ) do
    GenServer.reply(subscriber, {:ok, payload})

    Process.send_after(self(), :reschedule, interval)
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info(:send_tx, state = %{payload: payload}) do
    data = %TransactionData{content: payload}
    tx = Transaction.new(:oracle, data)
    :ok = Uniris.send_new_transaction(tx)

    {:noreply, state}
  end
end
