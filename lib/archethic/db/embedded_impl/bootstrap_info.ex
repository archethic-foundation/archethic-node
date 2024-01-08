defmodule Archethic.DB.EmbeddedImpl.BootstrapInfo do
  @moduledoc false

  use GenServer
  @vsn 1

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def get(key) when is_binary(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def set(key, value) when is_binary(key) and is_binary(value) do
    GenServer.cast(__MODULE__, {:set, key, value})
  end

  def init(opts \\ []) do
    db_path = Keyword.get(opts, :path)
    filepath = Path.join(db_path, "bootstrap")

    {:ok, %{data: %{}, filepath: filepath}, {:continue, :load_data}}
  end

  def handle_continue(:load_data, state = %{filepath: filepath}) do
    if File.exists?(filepath) do
      {:noreply, %{state | data: load_data(filepath)}}
    else
      {:noreply, state}
    end
  end

  def handle_call({:get, key}, _from, state = %{data: data}) do
    {:reply, Map.get(data, key), state}
  end

  def handle_cast({:set, key, value}, state = %{data: data, filepath: filepath}) do
    new_data = Map.put(data, key, value)
    store_on_disk(filepath, new_data)
    {:noreply, %{state | data: new_data}}
  end

  defp store_on_disk(filepath, data) do
    File.write!(filepath, :erlang.term_to_binary(data))
  end

  defp load_data(filepath) do
    data = File.read!(filepath)
    Plug.Crypto.non_executable_binary_to_term(data, [:safe])
  end
end
