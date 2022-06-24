defmodule Archethic.Utils.DetectNodeResponsiveness do
  @moduledoc """
  Detects the nodes responsiveness based on timeouts
  """
  @default_timeout 10 * 1000
  alias Archethic.P2P
  alias Archethic.DB

  use GenStateMachine
  require Logger

  def start_link(address, replaying_fn) do
    GenStateMachine.start_link(__MODULE__, [address, replaying_fn], [])
  end

  def init([address, replaying_fn]) do
    schedule_timeout()
    {:ok, :waiting, %{address: address, replaying_fn: replaying_fn, count: 1}}
  end

  def handle_event(
        :info,
        :soft_timeout,
        :waiting,
        state = %{
          address: address,
          replaying_fn: replaying_fn,
          count: count
        }
      ) do
    with false <- DB.transaction_exists?(address),
         true <- count < length(P2P.authorized_and_available_nodes()) do
      Logger.info("calling replay fn with count=#{count}")
      replaying_fn.(count)
      schedule_timeout()
      new_count = count + 1
      {:keep_state, %{state | count: new_count}}
    else
      # hard_timeout
      _ -> :stop
    end
  end

  defp schedule_timeout(interval \\ @default_timeout, pid \\ self()) do
    Process.send_after(pid, :soft_timeout, interval)
  end
end
