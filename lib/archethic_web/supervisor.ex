defmodule ArchethicWeb.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Networking

  alias ArchethicWeb.Endpoint
  alias ArchethicWeb.{FaucetRateLimiter, TransactionSubscriber, TransactionCache}
  alias ArchethicWeb.ExplorerLive.TopTransactionsCache

  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    # Try to open the HTTP port
    endpoint_conf = Application.get_env(:archethic, ArchethicWeb.Endpoint)

    try_open_port(Keyword.get(endpoint_conf, :http))
    try_open_port(Keyword.get(endpoint_conf, :https))

    children =
      [
        TransactionCache,
        TopTransactionsCache,
        {Phoenix.PubSub, [name: ArchethicWeb.PubSub, adapter: Phoenix.PubSub.PG2]},
        Endpoint,
        {Absinthe.Subscription, Endpoint},
        TransactionSubscriber,
        cache_child_spec()
      ]
      |> add_faucet_rate_limit_child()

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end

  defp try_open_port(nil), do: :ok

  defp try_open_port(conf) do
    port = Keyword.get(conf, :port)
    Networking.try_open_port(port, false)
  end

  defp add_faucet_rate_limit_child(children) do
    faucet_config = Application.get_env(:archethic, ArchethicWeb.FaucetController, [])

    if faucet_config[:enabled] do
      children ++ [FaucetRateLimiter]
    else
      children
    end
  end

  defp cache_child_spec() do
    %{
      id: :cache_lru_tx,
      start:
        {:lru, :start_link,
         [
           {:local, :cache_lru_tx},
           [max_size: Application.fetch_env!(:archethic_web, :tx_cache_bytes)]
         ]}
    }
  end
end
