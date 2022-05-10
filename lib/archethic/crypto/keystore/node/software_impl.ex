defmodule Archethic.Crypto.NodeKeystore.SoftwareImpl do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Crypto.ID
  alias Archethic.Crypto.Ed25519
  alias Archethic.Crypto.NodeKeystore

  alias Archethic.Utils

  @keystore_table :archethic_node_keystore

  @behaviour NodeKeystore

  use GenServer

  require Logger

  def start_link(arg \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  @impl NodeKeystore
  @spec first_public_key() :: Crypto.key()
  def first_public_key do
    get_public_key(:first_keypair)
  end

  @impl NodeKeystore
  @spec last_public_key() :: Crypto.key()
  def last_public_key do
    get_public_key(:last_keypair)
  end

  @impl NodeKeystore
  @spec next_public_key() :: Crypto.key()
  def next_public_key do
    get_public_key(:next_keypair)
  end

  @impl NodeKeystore
  @spec previous_public_key() :: Crypto.key()
  def previous_public_key do
    get_public_key(:previous_keypair)
  end

  @impl NodeKeystore
  @spec persist_next_keypair() :: :ok
  def persist_next_keypair do
    GenServer.call(__MODULE__, :persist_keypair)
  end

  @impl NodeKeystore
  @spec sign_with_first_key(iodata()) :: binary()
  def sign_with_first_key(data) do
    Crypto.sign(data, get_private_key(:first_keypair))
  end

  @impl NodeKeystore
  @spec sign_with_last_key(iodata()) :: binary()
  def sign_with_last_key(data) do
    Crypto.sign(data, get_private_key(:last_keypair))
  end

  @impl NodeKeystore
  @spec sign_with_previous_key(iodata()) :: binary()
  def sign_with_previous_key(data) do
    Crypto.sign(data, get_private_key(:previous_keypair))
  end

  @impl NodeKeystore
  @spec diffie_hellman_with_first_key(Crypto.key()) :: binary()
  def diffie_hellman_with_first_key(public_key) do
    [{_, {_, pv}}] = :ets.lookup(@keystore_table, :first_keypair)
    do_diffie_helmann(pv, public_key)
  end

  @impl NodeKeystore
  @spec diffie_hellman_with_last_key(Crypto.key()) :: binary()
  def diffie_hellman_with_last_key(public_key) do
    [{_, {_, pv}}] = :ets.lookup(@keystore_table, :last_keypair)
    do_diffie_helmann(pv, public_key)
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
  def init(opts) do
    # Initialize the crypto backup folder
    unless File.exists?(Utils.mut_dir("crypto")) do
      File.mkdir_p!(Utils.mut_dir("crypto"))
    end

    node_seed = Keyword.get(opts, :seed, read_seed())
    nb_keys = read_index()

    Logger.info("Start NodeKeystore at #{nb_keys}th key")

    # Derive keypairs from the node seed and from the index retrieved
    first_keypair = Crypto.derive_keypair(node_seed, 0)

    last_keypair =
      if nb_keys == 0 do
        first_keypair
      else
        Crypto.derive_keypair(node_seed, nb_keys - 1)
      end

    previous_keypair = Crypto.derive_keypair(node_seed, nb_keys)
    next_keypair = Crypto.derive_keypair(node_seed, nb_keys + 1)

    # Store the keypair in the ETS for fast access
    :ets.new(@keystore_table, [:set, :named_table, :protected, read_concurrency: true])

    set_keypair(:first_keypair, first_keypair)
    set_keypair(:last_keypair, last_keypair)
    set_keypair(:previous_keypair, previous_keypair)
    set_keypair(:next_keypair, next_keypair)

    :ets.insert(@keystore_table, {:seed, node_seed})
    :ets.insert(@keystore_table, {:index, nb_keys})

    {:ok, %{}}
  end

  defp read_seed do
    case File.read(seed_filepath()) do
      {:ok, seed} ->
        seed

      _ ->
        # We generate a random seed if no one is given
        seed = :crypto.strong_rand_bytes(32)

        # We write the seed on disk for backup later
        write_seed(seed)
        seed
    end
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

  defp write_seed(seed) when is_binary(seed) do
    File.write!(seed_filepath(), seed)
  end

  defp write_index(index) when is_integer(index) and index >= 0 do
    File.write!(index_filepath(), to_string(index))
  end

  defp seed_filepath, do: Utils.mut_dir("crypto/seed")
  defp index_filepath, do: Utils.mut_dir("crypto/index")

  defp set_keypair(keypair_name, keypair) when is_tuple(keypair) do
    true = :ets.insert(@keystore_table, {keypair_name, keypair})
    :ok
  end

  defp get_public_key(keypair_name) do
    [{_, {pub, _}}] = :ets.lookup(@keystore_table, keypair_name)
    pub
  end

  defp get_private_key(keypair_name) do
    [{_, {_, pv}}] = :ets.lookup(@keystore_table, keypair_name)
    pv
  end

  @impl GenServer
  def handle_call(:persist_keypair, _from, state) do
    # Retreive the seed and index
    [{_, index}] = :ets.lookup(@keystore_table, :index)
    [{_, node_seed}] = :ets.lookup(@keystore_table, :seed)

    # Derive the new keypairs
    next_keypair = Crypto.derive_keypair(node_seed, index + 2)
    previous_keypair = Crypto.derive_keypair(node_seed, index + 1)
    last_keypair = Crypto.derive_keypair(node_seed, index)

    # Update the new keypair as the chain advances
    set_keypair(:next_keypair, next_keypair)
    set_keypair(:previous_keypair, previous_keypair)
    set_keypair(:last_keypair, last_keypair)

    :ets.insert(@keystore_table, {:index, index + 1})

    Logger.info("Next public key will be #{Base.encode16(elem(next_keypair, 0))}")
    Logger.info("Previous public key will be #{Base.encode16(elem(previous_keypair, 0))}")
    Logger.info("Publication/Last public key will be #{Base.encode16(elem(last_keypair, 0))}")

    write_index(index + 1)
    {:reply, :ok, state}
  end
end
