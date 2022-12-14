defmodule ArchethicWeb.PlugThrottleByIPandPath do
  @moduledoc false
  use PlugAttack

  rule "Throttle by IP and Path", conn do
    [period: period, limit: limit] = Application.get_env(:archethic, :throttle)[:by_ip_and_path]

    throttle({conn.remote_ip, conn.path_info},
      period: period,
      limit: limit,
      storage: {PlugAttack.Storage.Ets, ArchethicWeb.PlugAttack.Storage}
    )
  end
end
