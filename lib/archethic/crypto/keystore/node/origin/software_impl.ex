defmodule Archethic.Crypto.NodeKeystore.Origin.SoftwareImpl do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.Crypto
  alias Archethic.Crypto.NodeKeystore.Origin

  alias Archethic.Utils

  @behaviour Origin

  def start_link(arg \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  @impl Origin
  def sign_with_origin_key(pid \\ __MODULE__, data) do
    GenServer.call(pid, {:sign_with_origin_key, data})
  end

  @impl Origin
  def origin_public_key(pid \\ __MODULE__) do
    GenServer.call(pid, :origin_public_key)
  end

  @impl Origin
  def retrieve_node_seed(pid \\ __MODULE__) do
    GenServer.call(pid, :retrieve_node_seed)
  end

  @impl GenServer
  def init(_arg \\ []) do
    unless File.exists?(Utils.mut_dir("crypto")) do
      File.mkdir_p!(Utils.mut_dir("crypto"))
    end

    origin_keypair = Crypto.generate_deterministic_keypair(read_origin_seed(), :secp256r1)
    node_seed = provision_node_seed()

    {:ok,
     %{
       origin_keypair: origin_keypair,
       node_seed: node_seed
     }}
  end

  @impl GenServer
  def handle_call({:sign_with_origin_key, data}, _, state = %{origin_keypair: {_pub, pv}}) do
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(:origin_public_key, _, state = %{origin_keypair: {pub, _}}) do
    {:reply, pub, state}
  end

  def handle_call(:retrieve_node_seed, _from, state = %{node_seed: node_seed}) do
    {:reply, node_seed, state}
  end

  defp provision_node_seed do
    seed =
      :archethic
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:node_seed)

    case seed do
      nil ->
        read_node_seed()

      seed ->
        case Base.decode16(seed, case: :mixed) do
          :error ->
            seed

          {:ok, seed} ->
            seed
        end
    end
  end

  defp read_origin_seed do
    case File.read(origin_seed_filename()) do
      {:ok, seed} ->
        seed

      _ ->
        seed =
          case System.get_env("ARCHETHIC_ORIGIN_SEED") do
            nil -> :crypto.strong_rand_bytes(32)
            value -> Base.decode16!(value)
          end

        File.write!(origin_seed_filename(), seed)
        seed
    end
  end

  defp origin_seed_filename, do: Utils.mut_dir("crypto/origin_seed")

  defp read_node_seed do
    case File.read(node_seed_filepath()) do
      {:ok, seed} ->
        seed

      _ ->
        # We generate a random seed if no one is given
        seed = :crypto.strong_rand_bytes(32)

        # We write the seed on disk for backup later
        write_node_seed(seed)
        seed
    end
  end

  defp write_node_seed(seed) when is_binary(seed) do
    File.write!(node_seed_filepath(), seed)
  end

  defp node_seed_filepath, do: Utils.mut_dir("crypto/node_seed")
end
