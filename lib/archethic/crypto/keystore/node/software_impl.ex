defmodule Archethic.Crypto.NodeKeystore.SoftwareImpl do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Crypto.ID
  alias Archethic.Crypto.Ed25519
  alias Archethic.Crypto.NodeKeystore
  alias Archethic.Crypto.NodeKeystore.Origin

  alias Archethic.Utils

  @keystore_table :archethic_node_keystore

  @behaviour NodeKeystore

  use GenServer
  @vsn 1

  require Logger

  def start_link(arg \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  @impl NodeKeystore
  @spec first_public_key() :: Crypto.key()
  def first_public_key do
    {pub, _} = Crypto.derive_keypair(get_node_seed(), 0)
    pub
  end

  @impl NodeKeystore
  @spec last_public_key() :: Crypto.key()
  def last_public_key do
    index = get_last_key_index()
    {pub, _} = Crypto.derive_keypair(get_node_seed(), index)
    pub
  end

  @impl NodeKeystore
  @spec next_public_key() :: Crypto.key()
  def next_public_key do
    index = get_next_key_index()
    {pub, _} = Crypto.derive_keypair(get_node_seed(), index)
    pub
  end

  @impl NodeKeystore
  @spec previous_public_key() :: Crypto.key()
  def previous_public_key do
    index = get_previous_key_index()
    {pub, _} = Crypto.derive_keypair(get_node_seed(), index)
    pub
  end

  @impl NodeKeystore
  @spec persist_next_keypair() :: :ok
  def persist_next_keypair do
    GenServer.call(__MODULE__, :persist_keypair)
  end

  @impl NodeKeystore
  @spec sign_with_first_key(iodata()) :: binary()
  def sign_with_first_key(data) do
    {_, pv} = Crypto.derive_keypair(get_node_seed(), 0)
    Crypto.sign(data, pv)
  end

  @impl NodeKeystore
  @spec sign_with_last_key(iodata()) :: binary()
  def sign_with_last_key(data) do
    index = get_last_key_index()
    {_, pv} = Crypto.derive_keypair(get_node_seed(), index)
    Crypto.sign(data, pv)
  end

  @impl NodeKeystore
  @spec sign_with_previous_key(iodata()) :: binary()
  def sign_with_previous_key(data) do
    index = get_previous_key_index()
    {_, pv} = Crypto.derive_keypair(get_node_seed(), index)
    Crypto.sign(data, pv)
  end

  @impl NodeKeystore
  @spec diffie_hellman_with_first_key(Crypto.key()) :: binary()
  def diffie_hellman_with_first_key(public_key) do
    {_, pv} = Crypto.derive_keypair(get_node_seed(), 0)
    do_diffie_helmann(pv, public_key)
  end

  @impl NodeKeystore
  @spec diffie_hellman_with_last_key(Crypto.key()) :: binary()
  def diffie_hellman_with_last_key(public_key) do
    index = get_last_key_index()
    {_, pv} = Crypto.derive_keypair(get_node_seed(), index)
    do_diffie_helmann(pv, public_key)
  end

  @impl NodeKeystore
  @spec sign_with_mining_key(iodata()) :: binary()
  def sign_with_mining_key(data) do
    {_, pv} = Crypto.generate_deterministic_keypair(get_node_seed(), :bls)
    Crypto.sign(data, pv)
  end

  @impl NodeKeystore
  @spec mining_public_key() :: binary()
  def mining_public_key do
    {pub, _} = Crypto.generate_deterministic_keypair(get_node_seed(), :bls)
    pub
  end

  defp get_last_key_index do
    [{_, index}] = :ets.lookup(@keystore_table, :last_index)
    index
  end

  defp get_previous_key_index do
    [{_, index}] = :ets.lookup(@keystore_table, :previous_index)
    index
  end

  defp get_next_key_index do
    [{_, index}] = :ets.lookup(@keystore_table, :next_index)
    index
  end

  defp get_node_seed do
    [{_, node_seed}] = :ets.lookup(@keystore_table, :node_seed)
    node_seed
  end

  defp do_diffie_helmann(<<curve_id::8, _origin_id::8, raw_pv::binary>>, public_key) do
    case ID.to_curve(curve_id) do
      :ed25519 ->
        x25519_sk = Ed25519.convert_to_x25519_private_key(raw_pv)
        :crypto.compute_key(:ecdh, public_key, x25519_sk, :x25519)

      curve ->
        :crypto.compute_key(:ecdh, public_key, raw_pv, curve)
    end
  end

  @impl GenServer
  def init(_arg \\ []) do
    :ets.new(@keystore_table, [:set, :named_table, :protected, read_concurrency: true])

    node_seed = Origin.retrieve_node_seed()
    :ets.insert(@keystore_table, {:node_seed, node_seed})

    unless File.exists?(Utils.mut_dir("crypto")) do
      File.mkdir_p!(Utils.mut_dir("crypto"))
    end

    nb_keys = read_index()

    # Store the indexes in the ETS for fast access
    store_node_key_indexes(nb_keys)

    Logger.info("Start NodeKeystore at #{nb_keys}th key")

    {:ok, %{}}
  end

  @impl NodeKeystore
  @spec set_node_key_index(index :: non_neg_integer()) :: :ok
  def set_node_key_index(index) do
    GenServer.call(__MODULE__, {:set_index, index})
  end

  defp store_node_key_indexes(index) do
    last_index =
      if index == 0 do
        0
      else
        index - 1
      end

    :ets.insert(@keystore_table, {:last_index, last_index})
    :ets.insert(@keystore_table, {:previous_index, index})
    :ets.insert(@keystore_table, {:next_index, index + 1})
  end

  defp read_index do
    case File.read(index_filepath()) do
      {:ok, ""} ->
        0

      {:ok, index} ->
        String.to_integer(index)

      _ ->
        write_index(0)
        0
    end
  end

  defp write_index(index) when is_integer(index) and index >= 0 do
    File.write!(index_filepath(), to_string(index))
  end

  defp index_filepath, do: Utils.mut_dir("crypto/index")

  @impl GenServer
  def handle_call(:persist_keypair, _from, state) do
    # Retreive the chain index
    index = get_previous_key_index()

    # Update the new indexes as the chain advances
    :ets.insert(@keystore_table, {:last_index, index})
    :ets.insert(@keystore_table, {:previous_index, index + 1})
    :ets.insert(@keystore_table, {:next_index, index + 2})

    node_seed = get_node_seed()
    {next_pub, _} = Crypto.derive_keypair(node_seed, index + 2)
    {previous_pub, _} = Crypto.derive_keypair(node_seed, index + 1)
    {last_pub, _} = Crypto.derive_keypair(node_seed, index)

    Logger.info("Next public key will be #{Base.encode16(next_pub)}")
    Logger.info("Previous public key will be #{Base.encode16(previous_pub)}")
    Logger.info("Publication/Last public key will be #{Base.encode16(last_pub)}")

    write_index(index + 1)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:set_index, index}, _from, state) do
    store_node_key_indexes(index)
    {:reply, :ok, state}
  end

  @impl GenServer
  # FIXME: use genserver message because ets table is protected
  def handle_cast(:migrate_1_5_6, state) do
    node_seed = Origin.retrieve_node_seed()
    :ets.insert(@keystore_table, {:node_seed, node_seed})
    :ets.delete(@keystore_table, :sign_fun)
    :ets.delete(@keystore_table, :public_key_fun)
    :ets.delete(@keystore_table, :dh_fun)

    {:noreply, state}
  end

  # FIXME: to remove after 1.5.6
  @doc false
  def migrate_ets_table_1_5_6 do
    GenServer.cast(__MODULE__, :migrate_1_5_6)
  end
end
