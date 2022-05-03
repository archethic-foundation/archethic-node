defmodule ArchEthicWeb.API.OriginKeyController do
  use ArchEthicWeb, :controller

  alias ArchEthic.Crypto
  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.TransactionData.Ownership

  def origin_key(conn, params) do
    with %{"origin_public_key" => origin_public_key} <- params,
         {:ok, origin_public_key} <- Base.decode16(origin_public_key, case: :mixed),
         true <- Crypto.valid_public_key?(origin_public_key),
         <<_curve_id::8, origin_id::8, _rest::binary>> <- origin_public_key,
         {first_origin_family_public_key, _} <-
           SharedSecrets.get_origin_family_from_origin_id(origin_id)
           |> SharedSecrets.get_origin_family_seed()
           |> Crypto.derive_keypair(0),
         {:ok, tx} <-
           Crypto.derive_address(first_origin_family_public_key)
           |> TransactionChain.get_last_transaction(data: [:ownerships]),
         ownership when ownership != nil <-
           Enum.find(tx.data.ownerships, fn ownership ->
             Ownership.authorized_public_key?(ownership, origin_public_key)
           end) do
      res = %{
        encrypted_origin_private_keys: Base.encode16(ownership.secret),
        encrypted_secret_key:
          Ownership.get_encrypted_key(ownership, origin_public_key) |> Base.encode16()
      }

      conn
      |> put_status(:ok)
      |> json(res)
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
