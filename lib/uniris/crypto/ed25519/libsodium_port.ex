defmodule Uniris.Crypto.Ed25519.LibSodiumPort do
  @moduledoc false
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    libsodium = Application.app_dir(:uniris, "/priv/c_dist/libsodium")

    port =
      Port.open({:spawn_executable, libsodium}, [
        :binary,
        :exit_status,
        {:packet, 4}
      ])

    {:ok, %{port: port, next_id: 1, awaiting: %{}}}
  end

  def handle_call(:generate_key, from, state) do
    {id, state} = send_request(state, 1)
    {:noreply, %{state | awaiting: Map.put(state.awaiting, id, from)}}
  end

  def handle_call({:generate_key, seed}, from, state) when is_binary(seed) do
    {id, state} = send_request(state, 2, seed)
    {:noreply, %{state | awaiting: Map.put(state.awaiting, id, from)}}
  end

  def handle_call({:encrypt, <<public_key::binary-32>>, data}, from, state)
      when is_binary(data) do
    {id, state} = send_request(state, 3, public_key <> <<byte_size(data)::32>> <> data)
    {:noreply, %{state | awaiting: Map.put(state.awaiting, id, from)}}
  end

  def handle_call({:decrypt, <<secret_key::binary-64>>, cipher}, from, state)
      when is_binary(cipher) do
    {id, state} = send_request(state, 4, secret_key <> <<byte_size(cipher)::32>> <> cipher)
    {:noreply, %{state | awaiting: Map.put(state.awaiting, id, from)}}
  end

  def handle_call({:sign, <<secret_key::binary-64>>, data}, from, state) when is_binary(data) do
    {id, state} = send_request(state, 5, secret_key <> <<byte_size(data)::32>> <> data)
    {:noreply, %{state | awaiting: Map.put(state.awaiting, id, from)}}
  end

  def handle_call({:verify, <<public_key::binary-32>>, data, <<sig::binary-64>>}, from, state)
      when is_binary(data) do
    {id, state} = send_request(state, 6, public_key <> <<byte_size(data)::32>> <> data <> sig)
    {:noreply, %{state | awaiting: Map.put(state.awaiting, id, from)}}
  end

  def handle_info({_port, {:data, <<req_id::32, response::binary>>} = _data}, state) do
    case state.awaiting[req_id] do
      nil ->
        {:noreply, state}

      caller ->
        case response do
          <<0::8, error_message::binary>> ->
            reason = String.to_atom(String.replace(error_message, " ", "_"))
            GenServer.reply(caller, {:error, reason})

          <<1::8>> ->
            GenServer.reply(caller, :ok)

          <<1::8, data::binary>> ->
            GenServer.reply(caller, {:ok, data})
        end

        {:noreply, %{state | awaiting: Map.delete(state.awaiting, req_id)}}
    end
  end

  def handle_info({_port, {:exit_status, status}}, _state) do
    :erlang.error({:port_exit, status})
  end

  defp send_request(state, request_type) do
    id = state.next_id
    Port.command(state.port, <<id::32>> <> <<request_type>>)
    {id, %{state | next_id: id + 1}}
  end

  defp send_request(state, request_type, data) do
    id = state.next_id
    Port.command(state.port, <<id::32>> <> <<request_type>> <> data)
    {id, %{state | next_id: id + 1}}
  end
end
