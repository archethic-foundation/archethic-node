defmodule ArchethicWeb.PlugAttack do
  @moduledoc false
  use PlugAttack

  rule "throttle by ip", conn do
    throttle(conn.remote_ip,
      period: 1_000,
      limit: 10,
      storage: {PlugAttack.Storage.Ets, ArchethicWeb.PlugAttack.Storage}
    )
  end
end
