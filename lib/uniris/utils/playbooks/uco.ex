defmodule Uniris.Playbook.UCO do
  @moduledoc """
  Play and verify UCO ledger.

  TODO
  """

  require Logger

  alias Uniris.Playbook
  alias Uniris.WebClient

  @behaviour Playbook

  @shared_secrets """
  query {shared_secrets {storage_nonce_public_key}}
  """

  @transactions """
  query {
    transactions {
      type,
      address,
      timestamp,
      data {
        recipients,
        ledger {
          nft {
            transfers {
              to
            }
          },

          uco {
            transfers {
              to
            }
          }
        }
      }
    }
  }
  """

  @doc """
  TODO
  """

  def transfer(_from, _to, _amount) do
    host = "node1"
    port = 4000

    timestamp = DateTime.utc_now()
    address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    previous_public_key = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    previous_signature = :crypto.strong_rand_bytes(64)
    origin_signature = :crypto.strong_rand_bytes(64)
    uco_to = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    # recipient = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    # secret = :crypto.strong_rand_bytes(32)
    # authorized_public_key = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    # encrypted_key = :crypto.strong_rand_bytes(32)

    tx = %{
      "address" => Base.encode16(address),
      "type" => "transfer",
      "timestamp" => DateTime.to_unix(timestamp, :millisecond),
      "previousPublicKey" => Base.encode16(previous_public_key),
      "previousSignature" => Base.encode16(previous_signature),
      "originSignature" => Base.encode16(origin_signature),
      "data" => %{
        "ledger" => %{
          "uco" => %{
            "transfers" => [
              %{"to" => Base.encode16(uco_to), "amount" => 12.34}
            ]
          }
        }
      }
    }

    # tx = %{
    #   "type" => "transfer",
    #   "address" => "005B287EBDF065F6081DCF8D7511B89FA1FD8FB1EB5538C8F4A22A854D08F451EF",
    #   "originSignature" =>
    #     "3A38C899C3BE2E20E4402CD28CDD6F6670515740B38CC50A6DD0F007" <>
    #       "FE828AF84B5F8E3495F1E39F247777920B27FE364460B4F68A467B9EFB491795F760CC83",
    #   "previousPublicKey" => "00A1F98CB38D2EF9154767164511D3C39B95518861FEE7A14CAFE209FDC7DD3556",
    #   "previousSignature" =>
    #     "86DC6AC9F0CBDBAAE006D772B9E351546139111BADC8D772AF68D9C4" <>
    #       "1FF540C88C3F8052C4DBF227146DDC1539A6B953FE7A574DD9348ADF74FB42D7B2139661",
    #   "timestamp" => System.os_time(:millisecond),
    #   "data" => %{
    #     "keys" => %{
    #       "authorizedKeys" => %{
    #         "0038E847194E94769B2E185A5BA8F17F038D3E1E9D32BDEB844B4544753B42BF5F" =>
    #           "C1884136D4E29D5037445F6A9BF1432BD69581498C4E43FE25C491C6A3FA9350"
    #       },
    #       "secret" => "D3D01CA5B390928269189ACDE0A6826F98E73484987FD48DB8D4339D4FA00F51"
    #     },
    #     "ledger" => %{
    #       "uco" => %{
    #         "transfers" => [
    #           %{
    #             "amount" => 10.2,
    #             "to" => "00B99DF9FA6CEFECF29913E2A5AE826ABC476C25EBD192738D5840D65EFDB7DF2E"
    #           }
    #         ]
    #       }
    #     },
    #     "recipients" => ["00038EDDB6A1514647E7292D422A1E1BC0295EB17EBC2115A0DBF68CB3B96EA643"]
    #   }
    # }

    {:ok, %{"status" => "ok"}} =
      WebClient.with_connection(host, port, &WebClient.json(&1, "/api/transaction", tx))

    address = "00B99DF9FA6CEFECF29913E2A5AE826ABC476C25EBD192738D5840D65EFDB7DF2E"
    query = ~s|query {balance(address: "#{address}"){uco}}|
    WebClient.with_connection(host, port, &WebClient.query(&1, query))
  end

  def play!(nodes, opts) do
    Logger.info("Play UCO transactions on #{inspect(nodes)} with #{inspect(opts)}")
    port = Application.get_env(:uniris, UnirisWeb.Endpoint)[:http][:port]
    host = :lists.nth(:rand.uniform(length(nodes)), nodes)

    {:ok, {secrets, transactions}} =
      WebClient.with_connection(host, port, fn conn ->
        with {:ok, conn, %{"data" => secrets}} <- WebClient.query(conn, @shared_secrets),
             {:ok, conn, %{"data" => transactions}} <- WebClient.query(conn, @transactions) do
          {:ok, conn, {secrets, transactions}}
        end
      end)

    Logger.info("Secrets #{inspect(secrets)}")
    %{"shared_secrets" => %{"storage_nonce_public_key" => pubkey}} = secrets
    Logger.info("#{host} pubkey is #{pubkey}")
    Logger.info("Transactions #{inspect(transactions)}")
  end
end
