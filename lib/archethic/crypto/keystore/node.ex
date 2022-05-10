defmodule Archethic.Crypto.NodeKeystore do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Crypto.ID
  alias Archethic.Crypto.Ed25519

  alias Archethic.DB

  alias Archethic.Utils

  @keystore_table :archethic_node_keystore
  @bootstrap_info_key "node_keys_index"

  use Knigge, otp_app: :archethic, delegate_at_runtime?: true

  @callback sign_with_origin_key(data :: iodata()) :: binary()
  @callback origin_public_key() :: Crypto.key()

  use GenServer

  require Logger

  def start_link(arg \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  def init(_arg) do
    :ets.new(@keystore_table, [:set, :named_table, :protected, read_concurrency: true])

    nb_keys =
      case DB.get_bootstrap_info(@bootstrap_info_key) do
        nil ->
          0

        index ->
          String.to_integer(index)
      end

    Logger.info("Start NodeKeystore at #{nb_keys}th key")

    case File.read(Utils.mut_dir("crypto/node_seed")) do
      {:ok, node_seed} ->
        first_keypair = Crypto.derive_keypair(node_seed, 0)

        last_keypair =
          if nb_keys == 0 do
            first_keypair
          else
            Crypto.derive_keypair(node_seed, nb_keys - 1)
          end

        previous_keypair = Crypto.derive_keypair(node_seed, nb_keys)
        next_keypair = Crypto.derive_keypair(node_seed, nb_keys + 1)

        :ets.insert(@keystore_table, {:first_keypair, first_keypair})
        :ets.insert(@keystore_table, {:last_keypair, last_keypair})
        :ets.insert(@keystore_table, {:previous_keypair, previous_keypair})
        :ets.insert(@keystore_table, {:next_keypair, next_keypair})
        :ets.insert(@keystore_table, {:seed, node_seed})

      {:error, :notent} ->
        node_seed = :crypto.strong_rand_bytes(32)
        File.write!(Utils.mut_dir("crypto/node_seed"), node_seed)

        first_keypair = Crypto.derive_keypair(node_seed, 0)
        last_keypair = first_keypair
        previous_keypair = Crypto.derive_keypair(node_seed, 0)
        next_keypair = Crypto.derive_keypair(node_seed, 1)

        :ets.insert(@keystore_table, {:first_keypair, first_keypair})
        :ets.insert(@keystore_table, {:last_keypair, last_keypair})
        :ets.insert(@keystore_table, {:previous_keypair, previous_keypair})
        :ets.insert(@keystore_table, {:next_keypair, next_keypair})
        :ets.insert(@keystore_table, {:seed, node_seed})
    end

    {:ok, %{}}
  end

  def first_public_key do
    [{_, {pub, _}}] = :ets.lookup(@keystore_table, :first_keypair)
    pub
  end

  def last_public_key do
    [{_, {pub, _}}] = :ets.lookup(@keystore_table, :last_keypair)
    pub
  end

  def next_public_key do
    [{_, {pub, _}}] = :ets.lookup(@keystore_table, :next_keypair)
    pub
  end

  def previous_public_key do
    [{_, {pub, _}}] = :ets.lookup(@keystore_table, :previous_keypair)
    pub
  end

  def persist_next_keypair do
    [{_, index}] = :ets.lookup(@keystore_table, :index)
    [{_, node_seed}] = :ets.lookup(@keystore_table, :seed)
    next_keypair = Crypto.derive_keypair(node_seed, index + 2)
    previous_keypair = Crypto.derive_keypair(node_seed, index + 1)
    last_keypair = Crypto.derive_keypair(node_seed, index)

    :ets.insert(@keystore_table, {:index, index + 1})
    :ets.insert(@keystore_table, {:next_keypair, next_keypair})
    :ets.insert(@keystore_table, {:previous_keypair, previous_keypair})
    :ets.insert(@keystore_table, {:last_keypair, last_keypair})

    Logger.info("Next public key will be #{Base.encode16(elem(next_keypair, 0))}")
    Logger.info("Previous public key will be #{Base.encode16(elem(previous_keypair, 0))}")
    Logger.info("Publication/Last public key will be #{Base.encode16(elem(last_keypair, 0))}")

    DB.set_bootstrap_info(@bootstrap_info_key, "#{index + 1}")
  end

  def sign_with_first_key(data) do
    [{_, {_, pv}}] = :ets.lookup(@keystore_table, :first_keypair)
    Crypto.sign(data, pv)
  end

  def sign_with_last_key(data) do
    [{_, {_, pv}}] = :ets.lookup(@keystore_table, :last_keypair)
    Crypto.sign(data, pv)
  end

  def sign_with_previous_key(data) do
    [{_, {_, pv}}] = :ets.lookup(@keystore_table, :previous_keypair)
    Crypto.sign(data, pv)
  end

  def diffie_hellman_with_first_key(public_key) do
    [{_, {_, pv}}] = :ets.lookup(@keystore_table, :first_keypair)
    do_diffie_helmann(pv, public_key)
  end

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
end
