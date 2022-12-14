defmodule ArchethicWeb.PlugThrottleByIP do
  @moduledoc false
  use PlugAttack

  rule "Throttle by IP", conn do
    [period: period, limit: limit] = Application.get_env(:archethic, :throttle)[:by_ip]

    throttle(conn.remote_ip,
      period: period,
      limit: limit,
      storage: {PlugAttack.Storage.Ets, ArchethicWeb.PlugAttack.Storage}
    )
  end
end
