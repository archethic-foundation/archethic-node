defmodule ArchethicWeb.Explorer.UpController do
  @moduledoc false

  use ArchethicWeb.Explorer, :controller

  @doc """
  The logic to respond 503 when node is not bootstraped is moved in a plug
  """
  def up(conn, _) do
    resp(conn, 200, "up")
  end
end
