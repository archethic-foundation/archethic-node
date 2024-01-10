defmodule Archethic.Reward.MemTables.RewardTokens do
  @moduledoc false

  use GenServer
  @vsn 1

  @reward_token_addresses_table :archethic_reward_token_addresses

  require Logger
  # server
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_args) do
    Logger.info("Initialize InMemory RewardToken Addresses...")
    :ets.new(@reward_token_addresses_table, [:set, :named_table, :public, read_concurrency: true])

    {:ok, %{}}
  end

  # api
  def add_reward_token_address(token_address) when is_binary(token_address) do
    true =
      :ets.insert(
        @reward_token_addresses_table,
        {token_address}
      )

    :ok
  end

  def exists?(token_address) when is_binary(token_address) do
    case :ets.lookup(@reward_token_addresses_table, token_address) do
      [{^token_address}] ->
        true

      [] ->
        false
    end
  end
end
