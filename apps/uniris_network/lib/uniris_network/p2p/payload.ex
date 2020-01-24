defmodule UnirisNetwork.P2P.Payload do
  @moduledoc false

  alias UnirisCrypto, as: Crypto

  @spec encode(term()) :: binary()
  def encode(payload) do
    binary_payload = :erlang.term_to_binary(payload)
    {:ok, public_key} = Crypto.last_public_key(:node)
    {:ok, sig} = Crypto.sign(binary_payload, source: :node, label: :last)
    public_key <> sig <> binary_payload
  end

  @spec decode(binary()) :: {:ok, term(), public_key :: <<_::264>>} | {:error, :invalid_payload}
  def decode(<<public_key::binary-33, signature::binary-64, binary_payload::binary>>) do
    case Crypto.verify(signature, binary_payload, public_key) do
      :ok ->
        payload = :erlang.binary_to_term(binary_payload, [:safe])
        {:ok, payload, public_key}

      _ ->
        {:error, :invalid_payload}
    end
  end

  def decode(_), do: {:error, :invalid_payload}
end
