defmodule Archethic.Crypto.NodeKeystore.Origin.SoftwareImpl do
  @moduledoc false

  use GenServer

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

  @impl GenServer
  @spec init(any) :: {:ok, %{origin_keypair: {<<_::16, _::_*8>>, <<_::16, _::_*8>>}}}
  def init(_arg \\ []) do
    origin_keypair = Crypto.generate_deterministic_keypair(read_seed())

    {:ok,
     %{
       origin_keypair: origin_keypair
     }}
  end

  @impl GenServer
  def handle_call({:sign_with_origin_key, data}, _, state = %{origin_keypair: {_pub, pv}}) do
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(:origin_public_key, _, state = %{origin_keypair: {pub, _}}) do
    {:reply, pub, state}
  end

  defp read_seed do
    unless File.exists?(Utils.mut_dir("crypto")) do
      File.mkdir_p!(Utils.mut_dir("crypto"))
    end

    case File.read(seed_filename()) do
      {:ok, seed} ->
        seed

      _ ->
        seed = :crypto.strong_rand_bytes(32)
        File.write!(seed_filename(), seed)
        seed
    end
  end

  defp seed_filename, do: Utils.mut_dir("crypto/origin_seed")
end
