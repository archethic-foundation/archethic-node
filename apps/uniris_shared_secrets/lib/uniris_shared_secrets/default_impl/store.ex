defmodule UnirisSharedSecrets.DefaultImpl.Store do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{usb: [], software: [], biometric: []}}
  end

  def handle_cast({:add_origin_public_key, family, public_key}, state) do
    {:noreply, Map.update!(state, family, &(&1 ++ [public_key]))}
  end

  def handle_call(:origin_public_keys, _, state) do
    {:reply, Map.values(state) |> Enum.flat_map(& &1), state}
  end

  def handle_call({:origin_public_keys, family}, _, state) do
    {:reply, Map.get(state, family), state}
  end

  def add_origin_public_key(family, public_key)
      when family in [:software, :usb, :biometric] and is_binary(public_key) do
    GenServer.cast(__MODULE__, {:add_origin_public_key, family, public_key})
  end

  def get_origin_public_keys() do
    GenServer.call(__MODULE__, :origin_public_keys)
  end

  def get_origin_public_keys(family) when family in [:software, :usb, :biometric] do
    GenServer.call(__MODULE__, {:origin_public_keys, family})
  end
end
