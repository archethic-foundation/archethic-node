defmodule Archethic.Bootstrap.NetworkConstraints do
  @moduledoc false

  alias Archethic.{
    Reward,
    SharedSecrets,
    OracleChain
  }

  require Logger

  @spec persist_genesis_address() :: :ok
  def persist_genesis_address() do
    persist(:oracle)

    res = %{
      reward: persist(:reward),
      node_shared_secrets: persist(:node_shared_secrets),
      origin: persist(:origin)
    }

    Logger.debug(
      "Gen Addr: reward: #{res.reward}, origin: #{res.origin}, nss: #{res.node_shared_secrets}"
    )

    if Enum.all?(res, fn {_k, v} -> v == :ok end) do
      Logger.info("Genesis Address Loading: Successful")
    else
      Logger.info("Genesis Address Loading: Failed, Resheduled to Next-Self-Repair")
    end

    :ok
  end

  @spec persist(:oracle | :reward | :origin | :node_shared_secrets) :: :ok | :error
  def persist(:reward) do
    case Reward.genesis_address() do
      nil ->
        Reward.persist_gen_addr()

      gen_addr when is_binary(gen_addr) ->
        :ok
    end
  end

  def persist(:origin) do
    case SharedSecrets.genesis_address(:origin) do
      nil ->
        SharedSecrets.persist_gen_addr(:origin)

      _gen_addr_list ->
        :ok
    end
  end

  def persist(:node_shared_secrets) do
    case SharedSecrets.genesis_address(:node_shared_secrets) do
      nil ->
        SharedSecrets.persist_gen_addr(:node_shared_secrets)

      gen_addr when is_binary(gen_addr) ->
        :ok
    end
  end

  def persist(:oracle) do
    try do
      OracleChain.update_summ_gen_addr()
      Logger.info("Oracle Gen Addr Table: Loaded")

      if gen_addr = OracleChain.genesis_address() do
        Logger.debug("New Oracle Gen Addr")
        Logger.debug(gen_addr)
      end

      :ok
    rescue
      _e ->
        Logger.info("Oracle Gen Addr Table: Failed ")

        :error
    end
  end
end
