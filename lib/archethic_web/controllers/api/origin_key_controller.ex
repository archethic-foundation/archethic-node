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
         <<_curve_id::8, origin_id::8, _rest::binary>> <- origin_public_key do
      signing_seed =
        origin_id
        |> Crypto.key_origin()
        |> SharedSecrets.get_origin_family_seed()

      {first_origin_family_public_key, _} = Crypto.derive_keypair(signing_seed, 0)

      address = Crypto.derive_address(first_origin_family_public_key)
      {:ok, last_address} = Archethic.get_last_transaction_address(address)
      {:ok, last_index} = Archethic.get_transaction_chain_length(last_address)

      tx =
        Transaction.new(
          :origin,
          %TransactionData{
            content: <<origin_public_key::binary, certificate::binary>>
          },
          signing_seed,
          last_index
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
