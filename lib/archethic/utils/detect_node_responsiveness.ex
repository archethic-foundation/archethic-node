defmodule Archethic.Utils.DetectNodeResponsiveness do
  @moduledoc """
  Detects the nodes responsiveness based on timeouts
  """
  @default_timeout Application.compile_env(:archethic, __MODULE__, [])
                   |> Keyword.get(:timeout, 5_000)

  alias Archethic.Mining

  alias Archethic.TransactionChain

  use GenServer
  @vsn 1
  require Logger

  def start_link(address, max_retry, replaying_fn, timeout \\ @default_timeout) do
    GenServer.start_link(__MODULE__, [address, max_retry, replaying_fn, timeout], [])
  end

  @spec init([...]) ::
          {:ok,
           %{address: any, count: 1, max_retry: any, replaying_fn: any, timeout: non_neg_integer}}
  def init([address, max_retry, replaying_fn, timeout]) do
    schedule_timeout(timeout)

    Logger.debug("Start node responsiveness worker", transaction_address: Base.encode16(address))

    {:ok,
     %{
       address: address,
       replaying_fn: replaying_fn,
       count: 1,
       max_retry: max_retry,
       timeout: timeout
     }}
  end

  def handle_info(
        :soft_timeout,
        state = %{
          address: address,
          replaying_fn: replaying_fn,
          count: count,
          max_retry: max_retry,
          timeout: timeout
        }
      ) do
    with {:exists, false} <- {:exists, TransactionChain.transaction_exists?(address)},
         {:mining, false} <- {:mining, Mining.processing?(address)},
         {:remaining, true} <- {:remaining, count < max_retry} do
      Logger.info("calling replay fn with count=#{count}",
        transaction_address: Base.encode16(address)
      )

      replaying_fn.(count)
      schedule_timeout(timeout)
      new_count = count + 1
      {:noreply, %{state | count: new_count}}
    else
      {:remaining, false} ->
        Logger.warning("Stop responsiveness because of hard timeout",
          transaction_address: Base.encode16(address)
        )

        {:stop, {:shutdown, :hard_timeout}, state}

      {:exists, true} ->
        Logger.debug("Stop responsiveness because transaction exists",
          transaction_address: Base.encode16(address)
        )

        {:stop, :normal, state}

      {:mining, true} ->
        Logger.debug("Reschedule responsiveness for transaction in mining process",
          transaction_address: Base.encode16(address)
        )

        # Reschedule timeout to wait for transaction to be validated
        schedule_timeout(timeout)
        {:noreply, state}
    end
  end

  def terminate(_, _state), do: :ok

  defp schedule_timeout(interval, pid \\ self()) do
    Process.send_after(pid, :soft_timeout, interval)
  end
end
