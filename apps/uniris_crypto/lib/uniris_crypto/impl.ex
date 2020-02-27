defmodule UnirisCrypto.Impl do
  @moduledoc false

  @callback derivate_keypair(
              index :: non_neg_integer(),
              options :: UnirisCrypto.key_generation_options()
            ) :: UnirisCrypto.key()

  @callback generate_random_keypair(options :: UnirisCrypto.key_generation_options()) ::
              UnirisCrypto.key()

  @callback generate_deterministic_keypair(
              seed :: binary(),
              options :: UnirisCrypto.key_generation_options()
            ) :: UnirisCrypto.key()

  @callback sign(data :: binary(), label :: UnirisCrypto.access_key_label()) :: binary()

  @callback verify(
              curve :: atom(),
              key :: UnirisCrypto.key(),
              data :: term,
              sig :: UnirisCrypto.signature()
            ) :: boolean()

  @callback ec_encrypt(curve :: atom(), public_key :: UnirisCrypto.key(), message :: binary()) ::
              binary()
  @callback ec_decrypt!(message :: binary(), label :: UnirisCrypto.access_key_label()) :: term()
  @callback aes_encrypt(data :: binary(), key :: UnirisCrypto.aes_key()) ::
              UnirisCrypto.aes_cipher()

  @callback aes_decrypt!(message :: UnirisCrypto.aes_cipher(), key :: UnirisCrypto.aes_key()) ::
              term()
  @callback first_node_public_key() :: UnirisCrypto.key()
  @callback last_node_public_key() :: UnirisCrypto.key()
  @callback previous_node_public_key() :: UnirisCrypto.key()
  @callback first_shared_public_key() :: UnirisCrypto.key()
  @callback last_shared_public_key() :: UnirisCrypto.key()

  @callback generate_shared_keys(
              seed :: binary(),
              last_index :: pos_integer(),
              curve :: UnirisCrypto.supported_curve()
            ) :: :ok

  @callback load_origin_keys(list({binary(), binary()})) :: :ok

  @callback generate_last_node_key(pos_integer()) :: :ok
end
