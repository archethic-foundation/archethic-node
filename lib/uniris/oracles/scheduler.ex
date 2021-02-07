defmodule Uniris.Oracles.Scheduler do
  @moduledoc false

  use GenServer

  alias Uniris.Oracles.TransactionContent

  alias Uniris.TransactionChain.{
    Transaction,
    TransactionData
  }

  alias Uniris.Utils

  # Public

  @spec start_link(mfa: mfa(), interval: String.t()) ::
          {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}
  def start_link(mfa: mfa, interval: interval) do
    ms_interval = parse_interval(interval)

    GenServer.start_link(__MODULE__, mfa: mfa, interval: ms_interval)
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
  def handle_continue(:prepare, state = %{mfa: {m, _, _}}) do
    m.start()

    Process.send_after(self(), :fetch, 0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_payload, subscriber, state = %{payload: nil, subscribers: subscribers}) do
    {:noreply, %{state | subscribers: [subscriber | subscribers]}}
  end

  @impl GenServer
  def handle_call(:get_payload, _, state = %{payload: payload}) do
    {:reply, payload, state}
  end

  @impl GenServer
  def handle_info(:fetch, state = %{mfa: {m, f, a}}) do
    args_with_date = [date: DateTime.utc_now()] ++ a

    payload =
      apply(m, f, args_with_date)
      |> :erlang.list_to_binary()

    Process.send_after(self(), :send_tx, 0)

    Process.send_after(self(), :reschedule, 0)
    {:noreply, %{state | payload: payload, mfa: {m, f, args_with_date}}}
  end

  @impl GenServer
  def handle_info(:reschedule, state = %{interval: interval, subscribers: []}) do
    Process.send_after(self(), :fetch, interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        :reschedule,
        state = %{interval: interval, payload: payload, subscribers: [subscriber | subscribers]}
      ) do
    GenServer.reply(subscriber, {:ok, payload})

    Process.send_after(self(), :reschedule, interval)
    {:noreply, %{state | subscribers: subscribers}}
  end

  @impl GenServer
  def handle_info(:send_tx, state = %{payload: payload, mfa: mfa}) do
    tx_content =
      %TransactionContent{mfa: mfa, payload: payload, status: :unverified}
      |> :erlang.term_to_binary()

    data = %TransactionData{content: tx_content}
    tx = Transaction.new(:oracle, data)
    :ok = Uniris.send_new_transaction(tx)

    {:noreply, state}
  end

  # Private

  @spec parse_interval(String.t()) :: milliseconds :: non_neg_integer()
  defp parse_interval(interval), do: Utils.time_offset(interval) * 1_000
end
