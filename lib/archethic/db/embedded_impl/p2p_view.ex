defmodule ArchEthic.DB.EmbeddedImpl.P2PView do
  @moduledoc false

  use GenServer

  alias ArchEthic.Crypto

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new node view from the last self-repair cycle 
  """
  @spec add_node_view(Crypto.key(), DateTime.t(), boolean(), float()) :: :ok
  def add_node_view(node_public_key, date = %DateTime{}, available?, avg_availability)
      when is_binary(node_public_key) and is_boolean(available?) and is_float(avg_availability) do
    GenServer.cast(
      __MODULE__,
      {:new_node_view, node_public_key, date, available?, avg_availability}
    )
  end

  @doc """
  Return the last node views from the last self-repair cycle
  """
  @spec get_views :: %{
          (node_public_key :: Crypto.key()) => {
            available? :: boolean(),
            average_availability :: float()
          }
        }
  def get_views do
    GenServer.call(__MODULE__, :get_node_views)
  end

  def init(opts) do
    db_path = Keyword.get(opts, :path)
    filepath = Path.join(db_path, "p2p_view")

    {:ok, %{filepath: filepath, views: %{}}, {:continue, :load_from_file}}
  end

  def handle_continue(:load_from_file, state = %{filepath: filepath}) do
    if File.exists?(filepath) do
      fd = File.open!(filepath, [:binary, :read])
      views = load_from_file(fd)
      new_state = Map.put(state, :views, views)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  defp load_from_file(fd, acc \\ %{}) do
    with {:ok, <<public_key_size::8>>} <- :file.read(fd, 1),
         {:ok,
          <<public_key::binary-size(public_key_size), timestamp::32, available::8,
            avg_availability::8>>} <- :file.read(fd, public_key_size + 6) do
      available? = if available == 1, do: true, else: false

      case Map.get(acc, public_key) do
        nil ->
          load_from_file(
            fd,
            Map.put(acc, public_key, %{
              available?: available?,
              avg_availability: avg_availability / 100,
              timestamp: timestamp
            })
          )

        %{timestamp: prev_timestamp} when timestamp > prev_timestamp ->
          load_from_file(
            fd,
            Map.put(acc, public_key, %{
              available?: available?,
              avg_availability: avg_availability / 100,
              timestamp: timestamp
            })
          )

        _ ->
          load_from_file(fd, acc)
      end
    else
      :eof ->
        Enum.map(acc, fn {node_public_key,
                          %{available?: available?, avg_availability: avg_availability}} ->
          {node_public_key, {available?, avg_availability}}
        end)
        |> Enum.into(%{})
    end
  end

  def handle_call(:get_node_views, _, state = %{views: views}) do
    {:reply, views, state}
  end

  def handle_cast(
        {:new_node_view, node_public_key, date, available?, avg_availability},
        state = %{filepath: filepath, views: views}
      ) do
    append_to_file(filepath, node_public_key, date, available?, avg_availability)
    new_views = Map.put(views, node_public_key, {available?, avg_availability})

    {:noreply, %{state | views: new_views}}
  end

  defp append_to_file(filepath, public_key, date, available?, avg_availability) do
    available_bit = if available?, do: 1, else: 0
    avg_availability_int = (avg_availability * 100) |> trunc()

    File.write!(
      filepath,
      <<byte_size(public_key)::8, public_key::binary, DateTime.to_unix(date)::32,
        available_bit::8, avg_availability_int::8>>,
      [:binary, :append]
    )
  end
end
