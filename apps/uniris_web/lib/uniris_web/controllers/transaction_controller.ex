defmodule UnirisWeb.TransactionController do
  use UnirisWeb, :controller

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Keys
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer

  def new(
        conn,
        params = %{
          "address" => address,
          "type" => type,
          "timestamp" => timestamp,
          "data" => %{
            "code" => code,
            "content" => content,
            "keys" => %{
              "secret" => secret,
              "authorizedKeys" => authorized_keys
            },
            "ledger" => %{
              "uco" => %{
                "transfers" => transfers
              }
            },
            "recipients" => recipients
          },
          "previousPublicKey" => previous_public_key,
          "previousSignature" => previous_signature,
          "originSignature" => origin_signature
        }
      ) do
    tx = %Transaction{
      address: Base.decode16!(address, case: :mixed),
      type: decode_type(type),
      timestamp: DateTime.from_unix!(timestamp, :millisecond),
      data: %TransactionData{
        content: content |> Base.decode16!(case: :mixed),
        code: code,
        keys: %Keys{
          secret: Base.decode16!(secret, case: :mixed),
          authorized_keys:
            Enum.reduce(authorized_keys, %{}, fn {publicKey, encryptedSecretKey}, acc ->
              Map.put(acc, Base.decode16!(publicKey, case: :mixed), Base.decode16!(encryptedSecretKey, case: :mixed))
            end)
        },
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers:
              Enum.map(transfers, fn %{"to" => to, "amount" => amount} ->
                %Transfer{
                  to: Base.decode16!(to, case: :mixed),
                  amount: amount
                }
              end)
          }
        },
        recipients: Enum.map(recipients, &Base.decode16!(&1, case: :mixed))
      },
      previous_public_key: Base.decode16!(previous_public_key, case: :mixed),
      previous_signature: Base.decode16!(previous_signature, case: :mixed),
      origin_signature: Base.decode16!(origin_signature, case: :mixed)
    }

    UnirisCore.send_new_transaction(tx)

    conn
    |> put_status(201)
    |> json(%{ status: "ok" })
  end

  defp decode_type("identity"), do: :identity
  defp decode_type("keychain"), do: :keychain
  defp decode_type("transfer"), do: :transfer
  defp decode_type("hosting"), do: :hosting

  def last_transaction_content(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <-
           UnirisCore.get_last_transaction(address) do
      mime_type = Map.get(params, "mime", "text/plain")

      etag = Base.encode16(last_address, case: :lower)

      status =
        case List.first(Plug.Conn.get_req_header(conn, "if-none-match")) do
          got_etag when got_etag == etag ->
            304

          _ ->
            200
        end

      conn
      |> put_resp_content_type(mime_type, "utf-8")
      |> put_resp_header("content-encoding", "gzip")
      |> put_resp_header("cache-control", "public")
      |> put_resp_header("etag", etag)
      |> send_resp(status, :zlib.gzip(content))
    else
      _reason ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
