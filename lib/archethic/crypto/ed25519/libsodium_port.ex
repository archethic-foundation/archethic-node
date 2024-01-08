defmodule Archethic.Crypto.Ed25519.LibSodiumPort do
  @moduledoc false
  use GenServer
  @vsn 1

  require Logger

  @table_name :libsodium_port

  alias Archethic.Utils.PortHandler

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Convert a ed25519 public key into a x25519
  """
  @spec convert_public_key_to_x25519(binary()) :: {:ok, binary()} | {:error, String.t()}
  def convert_public_key_to_x25519(<<public_key::binary-32>>) do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)
    PortHandler.request(port_handler, 1, public_key)
  end

  @doc """
  Convert a ed25519 secret key into a x25519
  """
  @spec convert_secret_key_to_x25519(binary()) :: {:ok, binary()} | {:error, String.t()}
  def convert_secret_key_to_x25519(<<secret_key::binary-64>>) do
    [{_, port_handler}] = :ets.lookup(@table_name, :port)
    PortHandler.request(port_handler, 2, secret_key)
  end

  def init(_opts) do
    libsodium = Application.app_dir(:archethic, "/priv/c_dist/libsodium_port")

    {:ok, port_handler} = PortHandler.start_link(program: libsodium)

    :ets.new(@table_name, [:set, :named_table, read_concurrency: true])
    :ets.insert(@table_name, {:port, port_handler})

    {:ok, %{}}
  end
end
