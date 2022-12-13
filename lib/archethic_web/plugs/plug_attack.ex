defmodule ArchethicWeb.PlugAttack do
  @moduledoc false
  use PlugAttack

  rule "throttle by ip", conn do
    [period: period, limit: limit] = Application.get_env(:archethic, :throttle)

    throttle(conn.remote_ip,
      period: period,
      limit: limit,
      storage: {PlugAttack.Storage.Ets, ArchethicWeb.PlugAttack.Storage}
    )
  end
end
