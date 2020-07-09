defmodule UnirisCore.SharedSecrets.Cache do
  @moduledoc false

  use GenServer

  @public_keys_table :uniris_shared_secrets_public_keys

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    :ets.new(@public_keys_table, [:bag, :named_table, :public, read_concurrency: true])
    {:ok, []}
  end

  @spec add_origin_public_key(
          family :: UnirisCore.SharedSecrets.origin_family(),
          key :: UnirisCore.Crypto.key()
        ) :: :ok
  def add_origin_public_key(family, key) do
    :ets.insert(@public_keys_table, {family, key})
  end

  @spec origin_public_keys() :: list(UnirisCore.Crypto.key())
  def origin_public_keys do
    select = [{{:"$1", :"$2"}, [], [:"$2"]}]
    :ets.select(@public_keys_table, select)
  end

  @spec origin_public_keys(family :: UnirisCore.SharedSecrets.origin_family()) ::
          list(UnirisCore.Crypto.key())
  def origin_public_keys(family) do
    select = [{{family, :"$1"}, [], [:"$1"]}]
    :ets.select(@public_keys_table, select)
  end
end
