defmodule ArchethicWeb.RouterDispatch do
  @moduledoc """
  This module is used to dispatch the connection between multiple routers
  """

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, opts) do
    routers = Keyword.get(opts, :routers, [])

    Enum.reduce_while(routers, nil, fn router, _acc ->
      try do
        conn = router.call(conn, [])
        {:halt, conn}
      rescue
        _ ->
          {:cont, nil}
      end
    end)
  end
end
