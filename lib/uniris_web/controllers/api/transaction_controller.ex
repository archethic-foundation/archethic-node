defmodule UnirisWeb.API.TransactionController do
  @moduledoc false

  use UnirisWeb, :controller

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.NFTLedger
  alias Uniris.TransactionChain.TransactionData.NFTLedger.Transfer, as: NFTTransfer
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  def new(conn, params = %{}) do
    tx = decode_pending_transaction(params)
    :ok = Uniris.send_new_transaction(tx)

    conn
    |> put_status(201)
    |> json(%{status: "ok"})
  end

  defp decode_pending_transaction(
         _params = %{
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
                 "transfers" => uco_transfers
               },
               "nft" => %{
                 "transfers" => nft_transfers
               }
             },
             "recipients" => recipients
           },
           "previousPublicKey" => previous_public_key,
           "previousSignature" => previous_signature,
           "originSignature" => origin_signature
         }
       ) do
    %Transaction{
      address: Base.decode16!(address, case: :mixed),
      type: decode_type(type),
      timestamp: DateTime.from_unix!(timestamp, :millisecond),
      data: %TransactionData{
        content: content |> Base.decode16!(case: :mixed),
        code: code,
        keys: %Keys{
          secret: Base.decode16!(secret, case: :mixed),
          authorized_keys:
            Enum.reduce(authorized_keys, %{}, fn {public_key, encrypted_secret_key}, acc ->
              Map.put(
                acc,
                Base.decode16!(public_key, case: :mixed),
                Base.decode16!(encrypted_secret_key, case: :mixed)
              )
            end)
        },
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers:
              Enum.map(uco_transfers, fn %{"to" => to, "amount" => amount} ->
                %UCOTransfer{
                  to: Base.decode16!(to, case: :mixed),
                  amount: amount
                }
              end)
          },
          nft: %NFTLedger{
            transfers:
              Enum.map(nft_transfers, fn %{"nft" => nft, "to" => to, "amount" => amount} ->
                %NFTTransfer{
                  nft: Base.decode16!(nft, case: :mixed),
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
  end

  defp decode_type("identity"), do: :identity
  defp decode_type("keychain"), do: :keychain
  defp decode_type("transfer"), do: :transfer
  defp decode_type("hosting"), do: :hosting
  defp decode_type("code_proposal"), do: :code_proposal
  defp decode_type("code_approval"), do: :code_approval
  defp decode_type("nft"), do: :nft

  def last_transaction_content(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <-
           Uniris.get_last_transaction(address) do
      mime_type = Map.get(params, "mime", "text/plain")

      etag = Base.encode16(last_address, case: :lower)

      cached? =
        case List.first(get_req_header(conn, "if-none-match")) do
          got_etag when got_etag == etag ->
            true

          _ ->
            false
        end

      conn =
        conn
        |> put_resp_content_type(mime_type, "utf-8")
        |> put_resp_header("content-encoding", "gzip")
        |> put_resp_header("cache-control", "public")
        |> put_resp_header("etag", etag)

      if cached? do
        send_resp(conn, 304, "")
      else
        send_resp(conn, 200, :zlib.gzip(content))
      end
    else
      _reason ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
