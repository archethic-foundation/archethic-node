defmodule ArchethicWeb.API.OriginKeyController do
  use ArchethicWeb, :controller

  alias Archethic.Crypto
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  def origin_key(conn, params) do
    with %{"origin_public_key" => origin_public_key, "certificate" => certificate} <- params,
         {:ok, origin_public_key} <- Base.decode16(origin_public_key, case: :mixed),
         true <- Crypto.valid_public_key?(origin_public_key),
         true <- Crypto.get_key_certificate(origin_public_key) == certificate,
         <<_curve_id::8, origin_id::8, _rest::binary>> <- origin_public_key do
      origin_family = Crypto.key_origin(origin_id)
      signing_seed = SharedSecrets.get_origin_family_seed(origin_family)

      tx =
        Transaction.new(
          :origin_shared_secrets,
          %TransactionData{
            content: <<origin_public_key::binary>>
          },
          signing_seed,
          0
        )

      Archethic.send_new_transaction(tx)

      conn
      |> put_status(:ok)
      |> json(%{status: "ok"})
    else
      er when er in [:error, false] ->
        conn
        |> put_status(400)
        |> json(%{
          error: "Invalid public key"
        })

      {:error, _} ->
        conn
        |> put_status(404)
        |> json(%{
          error: "Public key not found"
        })

      nil ->
        conn
        |> put_status(404)
        |> json(%{
          error: "Public key not found"
        })

      _ ->
        conn
        |> put_status(404)
        |> json(%{
          error: "Invalid parameters"
        })
    end
  end
end
