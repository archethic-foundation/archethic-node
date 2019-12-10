defmodule UnirisCrypto.Impl do
  @moduledoc false

  @callback derivate_keypair(
              index :: non_neg_integer(),
              options :: UnirisCrypto.key_generation_options()
            ) ::
              {:ok, UnirisCrypto.key()}
  @callback generate_random_keypair(options :: UnirisCrypto.key_generation_options()) ::
              {:ok, UnirisCrypto.key()}
  @callback generate_deterministic_keypair(
              seed :: binary(),
              options :: UnirisCrypto.key_generation_options()
            ) ::
              {:ok, UnirisCrypto.key()}

  @callback sign(data :: binary(), label :: UnirisCrypto.access_key_label()) ::
              {:ok, binary()} | {:error, :invalid_key}

  @callback verify(
              curve :: atom(),
              key :: UnirisCrypto.key(),
              data :: term,
              sig :: UnirisCrypto.signature()
            ) ::
              :ok | {:error, :invalid_signature}

  @callback ec_encrypt(curve :: atom(), public_key :: UnirisCrypto.key(), message :: binary()) ::
              {:ok, UnirisCrypto.cipher()}
  @callback ec_decrypt(message :: binary(), label :: UnirisCrypto.access_key_label()) ::
              {:ok, term()}
              | {:error, :inconsistent_curve_id}
              | {:error, :decryption_failed}
              | {:error, :invalid_key}
              | {:error, :invalid_cipher}

  @callback aes_encrypt(data :: binary(), key :: UnirisCrypto.aes_key()) ::
              UnirisCrypto.aes_cipher()
  @callback aes_decrypt(message :: UnirisCrypto.aes_cipher(), key :: UnirisCrypto.aes_key()) ::
              binary() | {:error, :decryption_failed}

  @callback get_public_key(UnirisCrypto.access_key_label()) ::
              {:ok, binary()} | {:error, :missing_key}
end
