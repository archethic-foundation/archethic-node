defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.FaucetEndpoint do
  @moduledoc """
  Contacts Testnet Faucet For UCOs
  """

  def main(recipient_address) do
    withdraw_uco({:https, "testnet.archethic.net", 443}, recipient_address)
  end

  def withdraw_uco({type, url, http_port}, wallet_address) do
    with {:ok, conn_ref} <- establish_connection(type, url, http_port),
         {:ok, conn, _req_ref} <- request(conn_ref, wallet_address) do
      stream_responses(conn)
    end
  end

  defp establish_connection(type, url, http_port) do
    Mint.HTTP.connect(type, url, http_port)
  end

  defp request(conn_ref, wallet_address) do
    {body, content_length} = get_request_body(wallet_address)
    header = get_request_header(content_length)

    Mint.HTTP.request(
      conn_ref,
      _method_type = "POST",
      _path = "/faucet",
      _header = header,
      _body = body
    )
  end

  def get_request_header(content_length) do
    [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Content-Length", "#{content_length}"},
      {"cookie",
       "_archethic_key=SFMyNTY.g3QAAAABbQAAAAtfY3NyZl90b2tlbm0AAAAYbnFtT0lVWE9ZZmVIVHZHQVdHenJKTzh2.AuLNklbvM6lHiGY2yGN6mmoDBNrcGqSL5v206ghydFs"}
    ]
  end

  def get_request_body(wallet_address) do
    body =
      "_csrf_token=DCcfJAc6Bz1sVl0ebAx-NhIlSgMMIH8DbVrkNo_r508V8z9wEb0qFoGu&address=#{wallet_address}"

    {body, body |> :erlang.byte_size()}
  end

  def stream_responses(conn) do
    receive do
      message ->
        with {:ok, conn, [{:status, _, 200}, {:headers, _, _}, {:data, _, _}, {:done, _}]} <-
               Mint.HTTP.stream(conn, message),
             {:ok, _} <- Mint.HTTP.close(conn) do
          {:ok, :transferred}
        end
    after
      5_000 ->
        {:error, :timeout}
    end
  end
end
