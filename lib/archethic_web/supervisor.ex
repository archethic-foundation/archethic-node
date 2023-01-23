defmodule ArchethicWeb.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Utils

  alias ArchethicCache.LRU
  alias ArchethicCache.LRUDisk
  alias ArchethicWeb.Endpoint
  alias ArchethicWeb.{FaucetRateLimiter, TransactionSubscriber, TransactionCache}
  alias ArchethicWeb.ExplorerLive.TopTransactionsCache

  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    children =
      [
        TransactionCache,
        TopTransactionsCache,
        {Phoenix.PubSub, [name: ArchethicWeb.PubSub, adapter: Phoenix.PubSub.PG2]},
        Endpoint,
        {Absinthe.Subscription, Endpoint},
        TransactionSubscriber,
        {PlugAttack.Storage.Ets, name: ArchethicWeb.PlugAttack.Storage, clean_period: 60_000},
        web_hosting_cache_ref_tx(),
        web_hosting_cache_file()
      ]
      |> add_faucet_rate_limit_child()

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end

  defp add_faucet_rate_limit_child(children) do
    faucet_config = Application.get_env(:archethic, ArchethicWeb.FaucetController, [])

    if faucet_config[:enabled] do
      children ++ [FaucetRateLimiter]
    else
      children
    end
  end

  # this is used in web_hosting_controller.ex
  # it does not store an entire transaction, but a triplet {address, json_content, timestamp}
  defp web_hosting_cache_ref_tx() do
    %{
      id: :web_hosting_cache_ref_tx,
      start:
        {LRU, :start_link,
         [
           :web_hosting_cache_ref_tx,
           web_hosting_config(:tx_cache_bytes)
         ]}
    }
  end

  defp web_hosting_cache_file() do
    %{
      id: :web_hosting_cache_file,
      start:
        {LRUDisk, :start_link,
         [
           :web_hosting_cache_file,
           web_hosting_config(:file_cache_bytes),
           Path.join(Utils.mut_dir(), "aeweb")
         ]}
    }
  end

  defp web_hosting_config(key) do
    config = Application.fetch_env!(:archethic, ArchethicWeb.API.WebHostingController)
    Keyword.get(config, key)
  end
end
