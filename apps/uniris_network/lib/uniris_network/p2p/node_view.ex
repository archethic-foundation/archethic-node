defmodule UnirisNetwork.P2P.NodeView do
  @moduledoc false
  @behaviour :gen_statem

  alias UnirisNetwork.NodeViewRegistry

  @ets_table :node_view_backup

  def child_spec(<<public_key::binary-33>>) do
    %{
      id: {__MODULE__, public_key},
      start: {__MODULE__, :start_link, [public_key]}
    }
  end

  @spec start_link(<<_::264>>) :: {:ok, pid()}
  def start_link(<<public_key::binary-33>>) do
    :gen_statem.start_link(via_tuple(public_key), __MODULE__, public_key, [])
  end

  def init(public_key) do
    Process.flag(:trap_exit, true)

    case :ets.lookup(@ets_table, public_key) do
      [{_, state}] ->
        {:ok, state, %{public_key: public_key}}

      _ ->
        {:ok, :idle, %{public_key: public_key}}
    end
  end

  def callback_mode, do: :state_functions

  def idle(:cast, :connected, data) do
    {:next_state, :available, data}
  end

  def idle(:cast, :disconnected, data) do
    {:next_state, :unavailable, data}
  end

  def available(:cast, :disconnected, data) do
    {:next_state, :unavailable, data}
  end

  def available(:cast, _, _) do
    :keep_state_and_data
  end

  def unavailable(:cast, :connected, data) do
    {:next_state, :available, data}
  end

  def unavailable(:cast, _, _) do
    :keep_state_and_data
  end

  def terminate(_reason, state, _data = %{public_key: public_key}) do
    :ets.insert(@ets_table, {public_key, state})
  end

  @spec connected(<<_::264>>) :: :ok
  def connected(<<node_public_key::binary-33>>) do
    :gen_statem.cast(via_tuple(node_public_key), :connected)
  end

  @spec disconnected(<<_::264>>) :: :ok
  def disconnected(<<node_public_key::binary-33>>) do
    :gen_statem.cast(via_tuple(node_public_key), :disconnected)
  end

  @spec status(<<_::264>>) :: :idle | :available | :unavailable
  def status(<<node_public_key::binary-33>>) do
    {state, _} = :sys.get_state(via_tuple(node_public_key))
    state
  end

  defp via_tuple(public_key) do
    {:via, Registry, {NodeViewRegistry, public_key}}
  end
end
