defmodule UnirisWeb.RootController do
  use UnirisWeb, :controller

  @uniris_io_tx_address "00CCB0371A3CA0775B73B0E9DE5175609411C1E470AF92F689A6E1B4F1DEF6C5C2"

  def index(conn, params) do
    params = params
    |> Map.put("address", @uniris_io_tx_address)
    |> Map.put("mime", "text/html")

    UnirisWeb.TransactionController.last_transaction_content(conn, params)
  end
end
