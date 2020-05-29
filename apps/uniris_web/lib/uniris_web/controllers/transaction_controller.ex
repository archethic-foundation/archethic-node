defmodule UnirisWeb.TransactionController do
  use UnirisWeb, :controller

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData

  def last_transaction_content(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address),
         {:ok, %Transaction{data: %TransactionData{content: content}}} <- UnirisCore.get_last_transaction(address) do

      mime_type = Map.get(params, "mime", "text/plain")

      conn
      |> put_resp_content_type(mime_type, "utf-8")
      |> send_resp(200, content)

    else
      _reason ->
        send_resp(conn, 404, "Not Found")
    end
  end

end
