defmodule Archethic.DB.EmbeddedImpl.P2PView do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.Crypto

  alias Archethic.Utils

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new nodes view from the last self-repair cycle
  """
  @spec set_node_view(list()) :: :ok
  def set_node_view(nodes_view) when is_list(nodes_view) do
    GenServer.cast(__MODULE__, {:set_node_view, nodes_view})
  end

  @doc """
  Return the last node views from the last self-repair cycle
  """
  @spec get_views() ::
          list(
            {node_public_key :: Crypto.key(), available? :: boolean(),
             average_availability :: float(), availability_update :: DateTime.t(),
             network_patch :: String.t() | nil}
          )
  def get_views() do
    GenServer.call(__MODULE__, :get_node_views)
  end

  def init(opts) do
    db_path = Keyword.get(opts, :path)
    filepath = Path.join(db_path, "p2p_view")

    {:ok, %{filepath: filepath, views: []}, {:continue, :load_from_file}}
  end

  def handle_continue(:load_from_file, state = %{filepath: filepath}) do
    if File.exists?(filepath) do
      data = File.read!(filepath)
      nodes_view = deserialize(data, [])
      new_state = Map.put(state, :views, nodes_view)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_call(:get_node_views, _, state = %{views: views}) do
    {:reply, views, state}
  end

  def handle_cast(
        {:set_node_view, nodes_view},
        state = %{filepath: filepath}
      ) do
    nodes_view_bin = serialize(nodes_view, <<>>)

    File.write!(filepath, nodes_view_bin, [:binary])

    {:noreply, %{state | views: nodes_view}}
  end

  defp serialize([], acc), do: acc

  defp serialize([view | rest], acc) do
    {node_key, available?, avg_availability, availability_update, network_patch} = view

    available_bit = if available?, do: 1, else: 0
    avg_availability_int = (avg_availability * 100) |> trunc()

    network_patch_bin =
      case network_patch do
        nil ->
          <<0::8>>

        _ ->
          <<1::8, network_patch::binary>>
      end

    acc =
      <<acc::bitstring, node_key::binary, available_bit::8, avg_availability_int::8,
        DateTime.to_unix(availability_update)::32, network_patch_bin::binary>>

    serialize(rest, acc)
  end

  defp deserialize(<<>>, acc), do: acc

  defp deserialize(data, acc) do
    {node_key,
     <<available_bit::8, avg_availability_int::8, availability_update::32, rest::bitstring>>} =
      Utils.deserialize_public_key(data)

    {network_patch, rest} =
      case rest do
        <<1::8, network_patch::binary-size(3), rest::bitstring>> ->
          {network_patch, rest}

        <<0::8, rest::bitstring>> ->
          {nil, rest}

        _ ->
          {nil, rest}
      end

    available? = if available_bit == 1, do: true, else: false

    view =
      {node_key, available?, avg_availability_int / 100, DateTime.from_unix!(availability_update),
       network_patch}

    deserialize(rest, [view | acc])
  end
end
