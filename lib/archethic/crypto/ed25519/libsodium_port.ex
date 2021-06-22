defmodule ArchEthic.Crypto.Ed25519.LibSodiumPort do
  @moduledoc false
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Convert a ed25519 public key into a x25519
  """
  @spec convert_public_key_to_x25519(binary()) :: {:ok, binary()} | {:error, String.t()}
  def convert_public_key_to_x25519(<<public_key::binary-32>>) do
    GenServer.call(__MODULE__, {:convert_public_key, public_key})
  end

  @doc """
  Convert a ed25519 secret key into a x25519
  """
  @spec convert_secret_key_to_x25519(binary()) :: {:ok, binary()} | {:error, String.t()}
  def convert_secret_key_to_x25519(<<secret_key::binary-64>>) do
    GenServer.call(__MODULE__, {:convert_secret_key, secret_key})
  end

  def init(_opts) do
    libsodium = Application.app_dir(:archethic, "/priv/c_dist/libsodium")

    port =
      Port.open({:spawn_executable, libsodium}, [
        :binary,
        :exit_status,
        {:packet, 4}
      ])

    {:ok, %{port: port, next_id: 1, awaiting: %{}}}
  end

  def handle_call({:convert_public_key, public_key}, from, state) do
    {id, state} = send_request(state, 1, public_key)
    {:noreply, %{state | awaiting: Map.put(state.awaiting, id, from)}}
  end

  def handle_call({:convert_secret_key, secret_key}, from, state) do
    {id, state} = send_request(state, 2, secret_key)
    {:noreply, %{state | awaiting: Map.put(state.awaiting, id, from)}}
  end

  def handle_info({_port, {:data, <<req_id::32, response::binary>>} = _data}, state) do
    case state.awaiting[req_id] do
      nil ->
        {:noreply, state}

      caller ->
        case response do
          <<0::8, error_message::binary>> ->
            GenServer.reply(caller, {:error, error_message})

          <<1::8, data::binary>> ->
            GenServer.reply(caller, {:ok, data})
        end

        {:noreply, %{state | awaiting: Map.delete(state.awaiting, req_id)}}
    end
  end

  def handle_info({_port, {:exit_status, status}}, _state) do
    :erlang.error({:port_exit, status})
  end

  defp send_request(state, request_type, data) do
    id = state.next_id
    Port.command(state.port, <<id::32, request_type::8, data::binary>>)
    {id, %{state | next_id: id + 1}}
  end
end
