defmodule Archethic.Crypto.NodeKeystore.TPMImpl do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Crypto.ID
  alias Archethic.Crypto.NodeKeystore

  alias Archethic.DB

  alias Archethic.Utils.PortHandler

  @behaviour NodeKeystore

  require Logger

  use GenServer

  @table_name :archethic_tpm_keystore
  @bootstrap_info_key "node_keys_index"

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl NodeKeystore
  @spec sign_with_first_key(data :: iodata()) :: binary()
  def sign_with_first_key(data) do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)
    sign(port_handler, 0, data)
  end

  @impl NodeKeystore
  @spec sign_with_last_key(data :: iodata()) :: binary()
  def sign_with_last_key(data) do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)
    [{_, last_index}] = :ets.lookup(@table_name, :last_index)
    sign(port_handler, last_index, data)
  end

  @impl NodeKeystore
  @spec sign_with_previous_key(data :: iodata()) :: binary()
  def sign_with_previous_key(data) do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)
    [{_, previous_index}] = :ets.lookup(@table_name, :previous_index)
    sign(port_handler, previous_index, data)
  end

  @impl NodeKeystore
  @spec sign_with_origin_key(data :: iodata()) :: binary()
  def sign_with_origin_key(data) do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)
    sign(port_handler, 0, data)
  end

  @impl NodeKeystore
  @spec last_public_key() :: Crypto.key()
  def last_public_key do
    [{_, public_key}] = :ets.lookup(@table_name, :last_public_key)
    public_key
  end

  @impl NodeKeystore
  @spec first_public_key() :: Crypto.key()
  def first_public_key do
    [{_, public_key}] = :ets.lookup(@table_name, :first_public_key)
    public_key
  end

  @impl NodeKeystore
  @spec previous_public_key() :: Crypto.key()
  def previous_public_key do
    [{_, public_key}] = :ets.lookup(@table_name, :previous_public_key)
    public_key
  end

  @impl NodeKeystore
  @spec next_public_key() :: Crypto.key()
  def next_public_key do
    [{_, public_key}] = :ets.lookup(@table_name, :next_public_key)
    public_key
  end

  @impl NodeKeystore
  @spec origin_public_key() :: Crypto.key()
  def origin_public_key do
    first_public_key()
  end

  @impl NodeKeystore
  @spec diffie_hellman_with_last_key(public_key :: Crypto.key()) :: binary()
  def diffie_hellman_with_last_key(public_key) when is_binary(public_key) do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)
    [{_, last_index}] = :ets.lookup(@table_name, :last_index)

    {:ok, <<_header::binary-size(1), z_x::binary-size(32), _z_y::binary-size(32)>>} =
      PortHandler.request(port_handler, 6, <<last_index::16, public_key::binary>>)

    z_x
  end

  @impl NodeKeystore
  @spec diffie_hellman_with_first_key(public_key :: Crypto.key()) :: binary()
  def diffie_hellman_with_first_key(public_key) when is_binary(public_key) do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)

    {:ok, <<_header::binary-size(1), z_x::binary-size(32), _z_y::binary-size(32)>>} =
      PortHandler.request(port_handler, 6, <<0::16, public_key::binary>>)

    z_x
  end

  @impl NodeKeystore
  @spec persist_next_keypair() :: :ok
  def persist_next_keypair do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)
    [{_, index}] = :ets.lookup(@table_name, :index)

    :ok = PortHandler.request(port_handler, 5, <<index + 1::16>>)

    DB.set_bootstrap_info(@bootstrap_info_key, "#{index + 1}")

    next_public_key = request_public_key(port_handler, index + 2)
    previous_public_key = request_public_key(port_handler, index + 1)
    last_public_key = request_public_key(port_handler, index)

    new_index = index + 1
    new_next_index = index + 2
    new_previous_index = index + 1
    new_last_index = index

    :ets.insert(@table_name, {:next_public_key, next_public_key})
    :ets.insert(@table_name, {:previous_public_key, previous_public_key})
    :ets.insert(@table_name, {:last_public_key, last_public_key})
    :ets.insert(@table_name, {:index, new_index})
    :ets.insert(@table_name, {:next_index, new_next_index})
    :ets.insert(@table_name, {:previous_index, new_previous_index})
    :ets.insert(@table_name, {:last_index, new_last_index})

    Logger.info("Next public key will be positied at #{new_next_index}")
    Logger.info("Previous public key will be positioned at #{new_previous_index}")
    Logger.info("Publication/Last public key will be positioned at #{new_last_index}")
  end

  @impl GenServer
  def init(_) do
    tpm_program = Application.app_dir(:archethic, "priv/c_dist/tpm_port")
    {:ok, port_handler} = PortHandler.start_link(program: tpm_program)

    case :ets.info(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        Logger.debug("TPM ETS table already created")
    end

    :ets.insert(@table_name, {:index, 0})
    :ets.insert(@table_name, {:port, port_handler})

    Process.monitor(port_handler)

    initialize_tpm(port_handler)

    {:ok, %{program: tpm_program}}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, _}, state = %{program: tpm_program}) do
    {:ok, port_handler} = PortHandler.start_link(program: tpm_program)
    :ets.insert(@table_name, {:port, port_handler})
    Process.monitor(port_handler)
    {:noreply, state}
  end

  defp request_public_key(port_handler, index) do
    {:ok, <<_::binary-size(26), public_key::binary>>} =
      PortHandler.request(port_handler, 2, <<index::16>>)

    ID.prepend_key(public_key, :secp256r1, :tpm)
  end

  defp set_index(port_handler, index) do
    :ok = PortHandler.request(port_handler, 5, <<index::16>>)
  end

  defp sign(port_handler, index, data) do
    hash = :crypto.hash(:sha256, data)
    start = System.monotonic_time()
    {:ok, sig} = PortHandler.request(port_handler, 3, <<index::16, hash::binary>>)

    :telemetry.execute([:archethic, :crypto, :tpm_sign], %{
      duration: System.monotonic_time() - start
    })

    sig
  end

  defp initialize_tpm(port_handler) do
    nb_keys =
      case DB.get_bootstrap_info(@bootstrap_info_key) do
        nil ->
          0

        index ->
          String.to_integer(index)
      end

    PortHandler.request(port_handler, 1, <<nb_keys::16>>)

    first_public_key = request_public_key(port_handler, 0)
    :ets.insert(@table_name, {:first_public_key, first_public_key})

    Logger.info("Start NodeKeystore at #{nb_keys}th key")

    last_index =
      if nb_keys == 0 do
        0
      else
        nb_keys - 1
      end

    last_public_key = request_public_key(port_handler, last_index)
    :ets.insert(@table_name, {:last_public_key, last_public_key})

    :ets.insert(
      @table_name,
      {:last_public_key, last_public_key}
    )

    previous_public_key = request_public_key(port_handler, nb_keys)
    :ets.insert(@table_name, {:previous_public_key, previous_public_key})

    next_public_key = request_public_key(port_handler, nb_keys + 1)
    :ets.insert(@table_name, {:next_public_key, next_public_key})

    set_index(port_handler, nb_keys)
    :ets.insert(@table_name, {:previous_index, nb_keys})
    :ets.insert(@table_name, {:last_index, last_index})
    :ets.insert(@table_name, {:next_index, nb_keys + 1})
  end
end
