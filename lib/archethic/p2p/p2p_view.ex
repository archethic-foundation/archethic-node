defmodule Archethic.P2P.P2PView do
  defstruct [
    :geo_patch,
    :available?,
    :avg_availability
  ]

  @type t :: %__MODULE__{
          geo_patch: binary(),
          available?: boolean(),
          avg_availability: float()
        }

  @archethic_db_p2pview :archethic_db_p2pview

  require Logger
  use GenServer

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    setup_ets_table()
    {:ok, %{}}
  end

  defp setup_ets_table, do: :ets.new(@archethic_db_p2pview, [:ordered_set, :named_table])

  @spec get_summary(timestamp :: DateTime.t()) :: list(t())
  def get_summary(timestamp) do
    DateTime.to_unix(timestamp)
    |> read_nodes()
    |> deserialize()
  end

  def get_p2p_view(timestamp, node_index_at_timestamp(first_public_key, timestamp))

  @spec update_node(
          changes :: Keyword.t(),
          start_timestamp :: DateTime.t(),
          index_at_timestamp :: (DateTime.t() -> integer())
        ) :: :ok
  def update_node(changes, start_timestamp, index_at_timestamp) do
    unix_start_timestamp = DateTime.to_unix(start_timestamp)

    changes = changes |> Enum.map(fn {key, value} -> {key, {value, true}} end)

    GenServer.call(
      __MODULE__,
      {:update_node, changes, unix_start_timestamp, index_at_timestamp}
    )
  end

  @spec add_node(
          node :: t(),
          start_timestamp :: DateTime.t(),
          index_at_timestamp :: (DateTime.t() -> integer())
        ) :: :ok
  def add_node(node, start_timestamp, index_at_timestamp) do
    unix_start_timestamp = DateTime.to_unix(start_timestamp)
    node_bin = serialize_node(node, true)
    GenServer.call(__MODULE__, {:add_node, node_bin, unix_start_timestamp, index_at_timestamp})
  end

  def handle_call({:update_node, changes, unix_start_timestamp, index_at_timestamp}, _from, state) do
    do_update_node(changes, unix_start_timestamp, index_at_timestamp)
    {:reply, :ok, state}
  end

  def handle_call({:add_node, node_bin, unix_start_timestamp, index_at_timestamp}, _from, state) do
    do_add_node(node_bin, unix_start_timestamp, index_at_timestamp)
    {:reply, :ok, state}
  end

  defp do_update_node(_, :"$end_of_table", _), do: :ok
  defp do_update_node([], _, _), do: :ok

  defp do_update_node(changes, unix_timestamp, index_at_timestamp) do
    node_index = index_at_timestamp.(DateTime.from_unix!(unix_timestamp))
    bin_p2p_view = read_nodes(unix_timestamp)

    {prefix, bin_node, suffix} = get_bin_node(bin_p2p_view, node_index)

    changes_to_apply =
      changes
      |> Enum.filter(&should_apply_change?(&1, bin_node))

    updated_node =
      bin_node
      |> apply_changes_to_node(changes_to_apply)

    (prefix <> updated_node <> suffix)
    |> write_nodes(unix_timestamp)

    changes_to_apply =
      changes_to_apply |> Enum.map(fn {key, {value, _}} -> {key, {value, false}} end)

    do_update_node(
      changes_to_apply,
      :ets.next(@archethic_db_p2pview, unix_timestamp),
      index_at_timestamp
    )
  end

  defp should_apply_change?({_, {nil, _}}, _) do
    false
  end

  defp should_apply_change?({key, {_, changed?}}, bin_node) do
    {_, previously_changed?} = get_bin_node_property(bin_node, key)
    changed? == true || previously_changed? != 1
  end

  defp do_add_node(_, :"$end_of_table", _), do: :ok

  defp do_add_node(node_bin, unix_timestamp, index_at_timestamp) do
    node_index = index_at_timestamp.(DateTime.from_unix!(unix_timestamp))

    read_nodes(unix_timestamp)
    |> insert_bin_node(node_index, node_bin)
    |> write_nodes(unix_timestamp)

    do_add_node(
      node_bin,
      :ets.next(@archethic_db_p2pview, unix_timestamp),
      index_at_timestamp
    )
  end

  # TODO decliner avec enregistrement sur fichier
  defp read_nodes(unix_timestamp) do
    case :ets.prev(@archethic_db_p2pview, unix_timestamp + 1) do
      :"$end_of_table" ->
        <<>>

      ^unix_timestamp = index ->
        :ets.lookup_element(@archethic_db_p2pview, index, 2)

      index ->
        :ets.lookup_element(@archethic_db_p2pview, index, 2)
        |> reset_bin_change_bits()
    end
  end

  # TODO decliner avec enregistrement sur fichier
  defp write_nodes(nodes, unix_timestamp) do
    :ets.insert(
      @archethic_db_p2pview,
      {unix_timestamp, nodes}
    )

    :ok
  end

  @bin_node_byte_size 8

  defp serialize(p2p_view, are_new_nodes?, acc \\ <<>>)

  defp serialize([], _, acc), do: acc

  defp serialize([node | rest], are_new_nodes?, acc) do
    node_bin = serialize_node(node, are_new_nodes?)

    serialize(
      rest,
      are_new_nodes?,
      acc <> node_bin
    )
  end

  defp serialize_node(
         %__MODULE__{
           geo_patch: geo_patch,
           available?: available?,
           avg_availability: avg_availability
         },
         is_new_node?
       ) do
    [{:geo_patch, geo_patch}, {:available?, available?}, {:avg_availability, avg_availability}]
    |> Enum.reduce(
      <<>>,
      &(&2 <> serialize_boolean(is_new_node?) <> serialize_node_property(&1))
    )
  end

  defp serialize_node_property({:geo_patch, value}), do: <<value::binary-size(3)>>
  defp serialize_node_property({:available?, value}), do: serialize_boolean(value)
  defp serialize_node_property({:avg_availability, value}), do: <<trunc(value * 100)::8>>

  defp serialize_boolean(true), do: <<1::8>>
  defp serialize_boolean(false), do: <<0::8>>

  defp deserialize(rest, acc \\ [])

  defp deserialize(<<>>, acc) do
    acc |> Enum.reverse()
  end

  defp deserialize(
         <<node_bin::binary-size(@bin_node_byte_size), rest::binary>>,
         acc
       ) do
    node = deserialize_node(node_bin)

    deserialize(rest, [node | acc])
  end

  defp deserialize_node(
         <<_::8, geo_patch::binary-size(3), _::8, available?, _::8, avg_availability::8>>
       ) do
    %__MODULE__{
      geo_patch: geo_patch,
      available?: available? == 1,
      avg_availability: avg_availability / 100
    }
  end

  # Helper functions for bin_node manipulation in binary form

  defp reset_bin_change_bits(bin_p2p_view, acc \\ <<>>)

  defp reset_bin_change_bits(<<>>, acc), do: acc

  defp reset_bin_change_bits(
         bin_p2p_view,
         acc
       ) do
    <<_::8, geo_patch::binary-size(3), _::8, available?::8, _::8, avg_availability::8,
      rest::binary>> = bin_p2p_view

    acc =
      <<acc::binary, 0::8, geo_patch::binary-size(3), 0::8, available?::8, 0::8,
        avg_availability::8>>

    reset_bin_change_bits(rest, acc)
  end

  defp get_bin_node(
         bin_p2p_view,
         index
       ) do
    prefix_size = @bin_node_byte_size * index

    <<prefix::binary-size(prefix_size), bin_node::binary-size(@bin_node_byte_size),
      suffix::binary>> = bin_p2p_view

    {prefix, bin_node, suffix}
  end

  defp get_bin_node_property(
         <<geo_patch_changed?::8, geo_patch::binary-size(3), _::binary>>,
         :geo_patch
       ) do
    {<<geo_patch::binary-size(3)>>, geo_patch_changed?}
  end

  defp get_bin_node_property(
         <<_::32, available_changed?::8, available?::8, _::binary>>,
         :available
       ) do
    {<<available?::8>>, available_changed?}
  end

  defp get_bin_node_property(
         <<_::48, avg_availability_changed?::8, avg_availability::8>>,
         :avg_availability
       ) do
    {<<avg_availability::8>>, avg_availability_changed?}
  end

  defp insert_bin_node(
         bin_p2p_view,
         index,
         bin_node
       ) do
    prefix_size = @bin_node_byte_size * index

    <<prefix::binary-size(prefix_size), suffix::binary>> = bin_p2p_view

    prefix <> bin_node <> suffix
  end

  defp apply_changes_to_node(
         bin_node,
         changes
       ) do
    [:geo_patch, :available, :avg_availability]
    |> Enum.reduce(<<>>, fn key, acc ->
      acc <>
        case changes[key] do
          nil ->
            {value, changed?} = get_bin_node_property(bin_node, key)
            <<changed?::8, value::binary>>

          {value, changed?} ->
            serialize_boolean(changed?) <> serialize_node_property({key, value})
        end
    end)
  end
end
