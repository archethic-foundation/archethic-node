defmodule Archethic.DB.EmbeddedImpl.Queue do
  @moduledoc false

  use GenServer

  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def init(_args) do
    {:ok, Map.new()}
  end

  @doc """
  Add a process in the queue for a specific genesis_address
  """
  @spec push(binary(), fun()) :: :ok
  def push(genesis_address, func) do
    GenServer.call(__MODULE__, {:push, genesis_address, func})
  end

  def handle_call({:push, genesis_address, func}, from, state) do
    new_state =
      Map.update(
        state,
        genesis_address,
        :queue.in({from, func}, :queue.new()),
        &:queue.in({from, func}, &1)
      )

    {:noreply, new_state, {:continue, genesis_address}}
  end

  def handle_continue(genesis_address, state) do
    case Map.get(state, genesis_address) do
      nil ->
        {:noreply, state}

      queue ->
        new_state =
          if :queue.is_empty(queue) do
            Map.delete(state, genesis_address)
          else
            Map.update!(state, genesis_address, fn _ ->
              {{:value, {from, func}}, queue} = :queue.out(queue)
              GenServer.reply(from, func.())
              queue
            end)
          end

        {:noreply, new_state, {:continue, genesis_address}}
    end
  end
end
