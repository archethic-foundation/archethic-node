defmodule ArchethicWeb.Plug.ThrottleByIPandPath do
  @moduledoc """
    Throttle requests based on the ip address
    and the path requested by the user
  """

  import Plug.Conn, only: [send_resp: 3, halt: 1]
  use PlugAttack

  rule "Throttle by IP and Path", conn do
    [period: period, limit: limit] = Application.get_env(:archethic, :throttle)[:by_ip_and_path]

    throttle({conn.remote_ip, conn.path_info},
      period: period,
      limit: limit,
      storage: {PlugAttack.Storage.Ets, ArchethicWeb.PlugAttack.Storage}
    )
  end

  def block_action(conn, _data, _opts) do
    conn
    |> send_resp(429, "Too many requests\n")
    |> halt
  end

  def allow_action(conn, _data, _opts), do: conn
end
