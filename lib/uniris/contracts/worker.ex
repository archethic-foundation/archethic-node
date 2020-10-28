defmodule Uniris.Contracts.Worker do
  @moduledoc false

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Interpreter

  alias Uniris.TransactionChain.Transaction
  alias Uniris.Utils

  use GenServer

  def start_link(contract = %Contract{constants: %{address: address}}) do
    GenServer.start_link(__MODULE__, contract, name: via_tuple(address))
  end

  @spec execute(binary(), Transaction.t()) :: :ok | {:error, :condition_not_respected}
  def execute(address, tx = %Transaction{}) do
    GenServer.call(via_tuple(address), {:execute, tx})
  end

  def init(contract = %Contract{triggers: triggers}) do
    Enum.each(triggers, fn {trigger_type, value} ->
      schedule_trigger(trigger_type, value)
    end)

    {:ok, %{contract: contract}}
  end

  def handle_call(
        {:execute, incoming_tx = %Transaction{}},
        _from,
        state = %{contract: contract}
      ) do
    case Interpreter.execute(put_in(contract, [:constants, :response], incoming_tx)) do
      :ok ->
        {:reply, :ok, state}

      {:error, _} = e ->
        {:reply, e, state}
    end
  end

  def handle_info(:datetime_trigger, state = %{contract: contract}) do
    Interpreter.execute(contract)
    {:noreply, state}
  end

  def handle_info({:interval_trigger, interval}, state = %{contract: contract}) do
    Interpreter.execute(contract)
    schedule_trigger(:interval_trigger, interval)
    {:noreply, state}
  end

  defp via_tuple(address) do
    {:via, Registry, {ContractRegistry, address}}
  end

  defp schedule_trigger(:interval, interval) do
    Process.send_after(self(), {:interval_trigger, interval}, Utils.time_offset(interval) * 1000)
  end

  defp schedule_trigger(:datetime, datetime = %DateTime{}) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime)
    Process.send_after(self(), :datetime_trigger, seconds * 1000)
  end
end
