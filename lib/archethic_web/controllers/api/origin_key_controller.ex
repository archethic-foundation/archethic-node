defmodule ArchethicWeb.API.OriginKeyController do
  use ArchethicWeb, :controller

  alias Archethic.Crypto
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias ArchethicWeb.TransactionSubscriber

  def origin_key(conn, params) do
    {status_code, response} =
      with %{"origin_public_key" => origin_public_key, "certificate" => certificate} <- params,
           {:ok, origin_public_key} <- Base.decode16(origin_public_key, case: :mixed),
           true <- Crypto.valid_public_key?(origin_public_key),
           <<_curve_id::8, origin_id::8, _rest::binary>> <- origin_public_key do
        origin_id
        |> prepare_transaction(origin_public_key, certificate)
        |> send_transaction()
      else
        error -> handle_error(error)
      end

    conn
    |> put_status(status_code)
    |> json(response)
  end

  defp prepare_transaction(origin_id, origin_public_key, certificate) do
    signing_seed =
      origin_id
      |> Crypto.key_origin()
      |> SharedSecrets.get_origin_family_seed()

    {first_origin_family_public_key, _} = Crypto.derive_keypair(signing_seed, 0)

    address = Crypto.derive_address(first_origin_family_public_key)

    with {:ok, last_address} <- Archethic.get_last_transaction_address(address),
         {:ok, last_index} <- Archethic.get_transaction_chain_length(last_address) do
      tx_content = <<origin_public_key::binary, certificate::binary>>

      Transaction.new(
        :origin,
        %TransactionData{
          content: tx_content
        },
        signing_seed,
        last_index
      )
    else
      error -> error
    end
  end

  defp send_transaction(%Transaction{} = tx) do
    case Archethic.send_new_transaction(tx) do
      :ok ->
        TransactionSubscriber.register(tx.address, System.monotonic_time())

        {201,
         %{
           transaction_address: Base.encode16(tx.address),
           status: "pending"
         }}

      {:error, :network_issue} ->
        {422, %{status: "error - may be invalid transaction"}}
    end
  end

  defp send_transaction(_) do
    {422, %{status: "error - may be invalid transaction"}}
  end

  defp handle_error(error) do
    case error do
      er when er in [:error, false] ->
        {400, %{status: "error - invalid public key"}}

      _ ->
        {400, %{status: "error - invalid parameters"}}
    end
  end
end
