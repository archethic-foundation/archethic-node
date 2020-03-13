defmodule UnirisSync.SelfRepair do
  @moduledoc false

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval)
    schedule_sync(interval)
    {:ok, %{interval: interval}}
  end

  def handle_info(:sync, state = %{interval: interval}) do
    Logger.info("Self-repair synchronization started")
    schedule_sync(interval)
    {:noreply, state}
  end

  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, interval)
  end
end
