defmodule Archethic.SharedSecrets.MemTables.OriginKeyLookup do
  @moduledoc """
  Represents a registry providing access to the origin public keys
  """

  use GenServer
  @vsn 1

  alias Archethic.Crypto

  alias Archethic.SharedSecrets

  require Logger

  @origin_key_table :archethic_origin_keys
  @origin_key_by_type_table :archethic_origin_key_by_type

  @doc """
  Initialize memory tables to index public information from the shared secrets

  ## Examples

      iex> {:ok, _} = OriginKeyLookup.start_link()
      ...> 
      ...> {:ets.info(:archethic_origin_keys)[:type],
      ...>  :ets.info(:archethic_origin_key_by_type)[:type]}
      {:set, :bag}
  """
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    Logger.info("Initialize InMemory Origin Key Lookup...")

    :ets.new(@origin_key_by_type_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@origin_key_table, [:set, :named_table, :public, read_concurrency: true])

    {:ok, []}
  end

  @doc """
  Add a new origin public key by giving its family: biometric, software, usb

  Family can be used in the smart contract to provide a level of security

  ## Examples

      iex> OriginKeyLookup.start_link()
      ...> :ok = OriginKeyLookup.add_public_key(:software, "key1")
      ...> :ok = OriginKeyLookup.add_public_key(:hardware, "key2")
      ...> :ok = OriginKeyLookup.add_public_key(:hardware, "key3")
      ...> {:ets.tab2list(:archethic_origin_keys), :ets.tab2list(:archethic_origin_key_by_type)}
      {
        [
          {"key1", :software},
          {"key2", :hardware},
          {"key3", :hardware}
        ],
        [
          {:hardware, "key2"},
          {:hardware, "key3"},
          {:software, "key1"}
        ]
      }
  """
  @spec add_public_key(
          family :: SharedSecrets.origin_family(),
          key :: Crypto.key()
        ) :: :ok
  def add_public_key(family, key) do
    true = :ets.insert(@origin_key_table, {key, family})
    true = :ets.insert(@origin_key_by_type_table, {family, key})
    :ok
  end

  @doc """
  Retrieve the origin public keys for a given family

  ## Examples

      iex> OriginKeyLookup.start_link()
      ...> :ok = OriginKeyLookup.add_public_key(:hardware, "key2")
      ...> :ok = OriginKeyLookup.add_public_key(:hardware, "key3")
      ...> OriginKeyLookup.list_public_keys(:hardware)
      ["key2", "key3"]
  """
  @spec list_public_keys(SharedSecrets.origin_family()) :: list(Crypto.key())
  def list_public_keys(family) do
    @origin_key_by_type_table
    |> :ets.lookup(family)
    |> Enum.map(fn {_, address} -> address end)
  end

  @doc """
  Retrieve all origin public keys across the families

  ## Examples

      iex> OriginKeyLookup.start_link()
      ...> :ok = OriginKeyLookup.add_public_key(:software, "key1")
      ...> :ok = OriginKeyLookup.add_public_key(:hardware, "key2")
      ...> :ok = OriginKeyLookup.add_public_key(:hardware, "key3")
      ...> OriginKeyLookup.list_public_keys()
      [
        "key1",
        "key2",
        "key3"
      ]
  """
  @spec list_public_keys() :: list(Crypto.key())
  def list_public_keys do
    select = [{{:"$1", :_}, [], [:"$1"]}]
    :ets.select(@origin_key_table, select)
  end

  @doc """
  Determines if the given public key is a registered origin public key

  ## Examples

      iex> OriginKeyLookup.start_link()
      ...> :ok = OriginKeyLookup.add_public_key(:software, "key1")
      ...> OriginKeyLookup.has_public_key?("key1")
      true
  """
  @spec has_public_key?(Crypto.key()) :: boolean()
  def has_public_key?(public_key) do
    :ets.member(@origin_key_table, public_key)
  end
end
