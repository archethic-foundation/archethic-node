defmodule Archethic.Utils.PortHandler do
  @moduledoc false

  use GenServer
  @vsn 1

  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def init(args) do
    program = Keyword.fetch!(args, :program)
    port = Port.open({:spawn_executable, program}, [:binary, :exit_status, {:packet, 4}])

    {:ok, %{port: port, next_id: 1, awaiting: %{}}}
  end

  @doc """
  Send a request to the port
  """
  @spec request(pid(), request_id :: non_neg_integer(), data :: binary()) ::
          {:ok, binary()} | :ok | {:error, binary()}
  def request(port_handler, request_id, data) when is_integer(request_id) and is_binary(data) do
    GenServer.call(port_handler, {:rpc, request_id, data})
  end

  def handle_call({:rpc, request_id, data}, from, state = %{next_id: id, port: port}) do
    send_request(id, port, request_id, data)

    next_state =
      state
      |> Map.update!(:next_id, &(&1 + 1))
      |> Map.update!(:awaiting, &Map.put(&1, id, from))

    {:noreply, next_state}
  end

  def handle_call({:rpc, request_id}, from, state = %{next_id: id, port: port}) do
    send_request(id, port, request_id)

    next_state =
      state
      |> Map.update!(:next_id, &(&1 + 1))
      |> Map.update!(:awaiting, &Map.put(&1, id, from))

    {:noreply, next_state}
  end

  def handle_info(
        {_port, {:data, <<request_id::32, response::binary>>}},
        state = %{awaiting: awaiting}
      ) do
    case Map.pop(awaiting, request_id) do
      {nil, awaiting} ->
        {:noreply, %{state | awaiting: awaiting}}

      {client, awaiting} ->
        case response do
          <<0::8, error_message::binary>> ->
            GenServer.reply(client, {:error, error_message})

          <<1::8>> ->
            GenServer.reply(client, :ok)

          <<1::8, data::binary>> ->
            GenServer.reply(client, {:ok, data})
        end

        {:noreply, %{state | awaiting: awaiting}}
    end
  end

  def handle_info({_port, {:exit_status, status}}, state) do
    :erlang.error({:port_exit, status})
    {:noreply, state}
  end

  defp send_request(id, port, request_id, data \\ "") do
    Port.command(port, <<id::32, request_id::8, data::binary>>)
  end
end
