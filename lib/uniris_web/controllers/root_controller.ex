defmodule UnirisWeb.RootController do
  @moduledoc false

  use UnirisWeb, :controller

  alias UnirisWeb.API.TransactionController

  @uniris_io_tx_address "00CCB0371A3CA0775B73B0E9DE5175609411C1E470AF92F689A6E1B4F1DEF6C5C2"

  # TODO: Get the TX address from DNSLink from the host referral otherwise redirect to the explorer
  def index(conn, params) do
    params =
      params
      |> Map.put("address", @uniris_io_tx_address)
      |> Map.put("mime", "text/html")

    TransactionController.last_transaction_content(conn, params)
  end
end
