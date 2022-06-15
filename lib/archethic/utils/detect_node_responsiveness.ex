defmodule Archethic.Utils.DetectNodeResponsiveness do
  @moduledoc """
  Detects the nodes responsiveness based on timeouts
  """
  @default_timeout 3 * 1000
  alias Archethic.PubSub
  alias Archethic.P2P

  use GenStateMachine

  def start_link(address, replaying_fn) do
    GenStateMachine.start_link(__MODULE__, [address, replaying_fn], [])
  end

  def init([address, replaying_fn]) do
    PubSub.register_to_new_transaction_by_address(address)
    schedule_timeout()
    {:ok, :waiting, %{address: address, replaying_fn: replaying_fn, count: 0}}
  end

  def handle_event(:info, :soft_timeout, :waiting, %{replaying_fn: replaying_fn, count: count}) do
    if count < length(P2P.authorized_and_available_nodes()) do
      replaying_fn.(count)
      schedule_timeout()
      count = count + 1
      {:keep_state, %{count: count, replaying_fn: replaying_fn}}
    else
      # hard_timeout

      :stop
    end
  end

  def handle_event(:info, {:new_transaction, _, _, _}, :waiting, _) do
    :stop
  end

  defp schedule_timeout(interval \\ @default_timeout, pid \\ self()) do
    Process.send_after(pid, :soft_timeout, interval)
  end
end
