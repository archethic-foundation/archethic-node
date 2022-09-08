defmodule Archethic.Utils.DetectNodeResponsiveness do
  @moduledoc """
  Detects the nodes responsiveness based on timeouts
  """
  @default_timeout Application.compile_env(:archethic, __MODULE__, [])
                   |> Keyword.get(:timeout, 5_000)
  alias Archethic.P2P
  alias Archethic.DB
  alias Archethic.Mining

  use GenServer
  require Logger

  def start_link(address, replaying_fn, timeout \\ @default_timeout) do
    GenServer.start_link(__MODULE__, [address, replaying_fn, timeout], [])
  end

  def init([address, replaying_fn, timeout]) do
    schedule_timeout(timeout)

    Logger.debug("Start node responsivessness worker", transaction_address: Base.encode16(address))

    {:ok, %{address: address, replaying_fn: replaying_fn, count: 1, timeout: timeout}}
  end

  def handle_info(
        :soft_timeout,
        state = %{
          address: address,
          replaying_fn: replaying_fn,
          count: count,
          timeout: timeout
        }
      ) do
    remaning? = count < length(P2P.authorized_and_available_nodes())

    with {:exists, false} <- {:exists, DB.transaction_exists?(address)},
         {:mining, false} <- {:mining, Mining.processing?(address)},
         {:remaining, true} <- {:remaining, remaning?} do
      Logger.info("calling replay fn with count=#{count}",
        transaction_address: Base.encode16(address)
      )

      replaying_fn.(count)
      schedule_timeout(timeout)
      new_count = count + 1
      {:noreply, %{state | count: new_count}}
    else
      {:remaining, false} ->
        {:stop, {:shutdown, :hard_timeout}, state}

      {reason, _} ->
        Logger.debug("Stop responsiveness because of #{reason}",
          transaction_address: Base.encode16(address)
        )

        {:stop, :normal, state}
    end
  end

  def terminate(_, _state), do: :ok

  defp schedule_timeout(interval, pid \\ self()) do
    Process.send_after(pid, :soft_timeout, interval)
  end
end
