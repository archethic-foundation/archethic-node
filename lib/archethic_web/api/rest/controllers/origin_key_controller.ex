defmodule ArchethicWeb.API.REST.OriginKeyController do
  use ArchethicWeb.API, :controller

  alias ArchethicWeb.API.OriginPublicKeyPayload

  alias ArchethicWeb.TransactionSubscriber

  alias Archethic.Crypto
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.Transaction

  @spec origin_key(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def origin_key(conn, params = %{}) do
    case OriginPublicKeyPayload.changeset(params) do
      %{
        valid?: true,
        changes: %{origin_public_key: origin_public_key, certificate: certificate}
      } ->
        <<_curve_id::8, origin_id::8, _rest::binary>> = origin_public_key

        {status_code, response} =
          origin_id
          |> prepare_transaction(origin_public_key, certificate)
          |> send_transaction()

        conn
        |> put_status(status_code)
        |> json(response)

      changeset ->
        conn
        |> put_status(400)
        |> put_view(ArchethicWeb.Explorer.ErrorView)
        |> render("400.json", changeset: changeset)
    end
  end

  defp prepare_transaction(origin_id, origin_public_key, certificate) do
    signing_seed =
      origin_id
      |> Crypto.key_origin()
      |> SharedSecrets.get_origin_family_seed()

    {first_origin_family_public_key, _} = Crypto.derive_keypair(signing_seed, 0)

    last_index =
      first_origin_family_public_key
      |> Crypto.derive_address()
      |> TransactionChain.get_size()

    tx_content = <<origin_public_key::binary, byte_size(certificate)::16, certificate::binary>>

    Transaction.new(
      :origin,
      %TransactionData{
        code:
          TransactionData.compress_code("""
            condition inherit: [
              # We need to ensure the type stays consistent
              # So we can apply specific rules during the transaction validation
              type: origin,
              content: true
            ]
          """),
        content: tx_content
      },
      signing_seed,
      last_index
    )
  end

  defp send_transaction(tx = %Transaction{}) do
    :ok = Archethic.send_new_transaction(tx, forward?: true)
    TransactionSubscriber.register(tx.address, System.monotonic_time())

    {201,
     %{
       transaction_address: Base.encode16(tx.address),
       status: "pending"
     }}
  end
end
