defmodule ArchethicWeb.API.JsonRPC.Method.AddOriginKey do
  @moduledoc """
  JsonRPC method to add a new origin public key to be used in proof of work
  """

  alias Archethic.Crypto

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.API.OriginPublicKeyPayload

  alias ArchethicWeb.TransactionSubscriber

  alias ArchethicWeb.WebUtils

  @behaviour Method

  @doc """
  Validate parameter to match the expected JSON pattern
  """
  @spec validate_params(param :: map()) ::
          {:ok, params :: map()} | {:error, reasons :: map()}
  def validate_params(params) do
    case OriginPublicKeyPayload.changeset(params) do
      %{valid?: true, changes: changes} ->
        {:ok, changes}

      changeset ->
        reasons = Ecto.Changeset.traverse_errors(changeset, &WebUtils.translate_error/1)

        {:error, reasons}
    end
  end

  @doc """
  Execute the function to send a new tranaction in the network
  """
  @spec execute(params :: map()) :: {:ok, result :: map()}
  def execute(%{origin_public_key: origin_public_key, certificate: certificate}) do
    <<_curve_id::8, origin_id::8, _rest::binary>> = origin_public_key

    tx = prepare_transaction(origin_id, origin_public_key, certificate)

    :ok = Archethic.send_new_transaction(tx, forward?: true)
    TransactionSubscriber.register(tx.address, System.monotonic_time())

    result = %{transaction_address: Base.encode16(tx.address), status: "pending"}
    {:ok, result}
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
end
