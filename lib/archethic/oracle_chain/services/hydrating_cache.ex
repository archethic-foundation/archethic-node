defmodule Archethic.OracleChain.Services.HydratingCache do
  @moduledoc """
  This module is responsible for :
  - Run the hydrating function associated with this key at a given interval
  - Discard the value after some time
  - Return the value when requested
  """
  use GenServer

  defmodule State do
    @moduledoc false
    defstruct([
      :mfa,
      :ttl,
      :ttl_ref,
      :refresh_interval,
      :value,
      :hydrating_task
    ])
  end

  @spec start_link(keyword()) ::
          {:ok, GenServer.on_start()} | {:error, term()}
  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, Keyword.take(arg, [:name]))
  end

  @spec get(GenServer.server(), integer()) :: {:ok, any()} | :error
  def get(server, timeout \\ 5000) do
    try do
      GenServer.call(server, :get, timeout)
    catch
      :exit, {:timeout, _} ->
        :error
    end
  end

  def init(options) do
    refresh_interval = Keyword.fetch!(options, :refresh_interval)
    mfa = Keyword.fetch!(options, :mfa)
    ttl = Keyword.get(options, :ttl, :infinity)

    # start hydrating as soon as init is done
    Process.send_after(self(), :hydrate, 0)

    ## Hydrate the value
    {:ok,
     %State{
       mfa: mfa,
       ttl: ttl,
       refresh_interval: refresh_interval
     }}
  end

  def handle_call(:get, _from, state = %State{value: nil}) do
    {:reply, :error, state}
  end

  def handle_call(:get, _from, state = %State{value: value}) when value != nil do
    {:reply, {:ok, value}, state}
  end

  def handle_info(
        :hydrate,
        state = %State{
          refresh_interval: refresh_interval,
          mfa: {m, f, a}
        }
      ) do
    hydrating_task =
      Task.async(fn ->
        try do
          {:ok, apply(m, f, a)}
        rescue
          _ ->
            :error
        end
      end)

    # start a new hydrate timer
    Process.send_after(self(), :hydrate, refresh_interval)

    {:noreply, %State{state | hydrating_task: hydrating_task}}
  end

  def handle_info(
        {ref, result},
        state = %State{ttl_ref: ttl_ref, ttl: ttl, hydrating_task: %Task{ref: ref_task}}
      )
      when ref == ref_task do
    # cancel current ttl if any
    if is_reference(ttl_ref) do
      Process.cancel_timer(ttl_ref)
    end

    # start new ttl timer
    ttl_ref =
      if is_integer(ttl) do
        Process.send_after(self(), :discard_value, ttl)
      else
        nil
      end

    new_state = %{state | ttl_ref: ttl_ref, hydrating_task: nil}

    case result do
      {:ok, value} ->
        {:noreply, %{new_state | value: value}}

      _ ->
        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _, _}, state), do: {:noreply, state}

  def handle_info(:discard_value, state) do
    {:noreply, %State{state | value: nil, ttl_ref: nil}}
  end
end
