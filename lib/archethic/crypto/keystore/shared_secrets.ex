defmodule Archethic.Crypto.SharedSecretsKeystore do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Crypto.SharedSecretsKeystore.SoftwareImpl

  use Knigge, otp_app: :archethic, default: SoftwareImpl, delegate_at_runtime?: true

  @callback child_spec(any()) :: Supervisor.child_spec()

  @callback sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  @callback sign_with_node_shared_secrets_key(data :: binary(), index :: non_neg_integer()) ::
              binary()
  @callback sign_with_reward_key(data :: binary()) :: binary()
  @callback sign_with_reward_key(data :: binary(), index :: non_neg_integer()) :: binary()
  @callback sign_with_daily_nonce_key(data :: binary(), DateTime.t()) :: binary()

  @callback node_shared_secrets_public_key(index :: non_neg_integer()) :: Crypto.key()
  @callback reward_public_key(index :: non_neg_integer()) :: Crypto.key()

  @callback wrap_secrets(key :: binary()) ::
              {enc_transaction_seed :: binary(), enc_reward_seed :: binary()}

  @callback unwrap_secrets(
              encrypted_secrets :: binary(),
              encrypted_secret_key :: binary(),
              date :: DateTime.t()
            ) :: :ok | :error

  @callback get_reward_key_index() :: non_neg_integer()
  @callback set_reward_key_index(non_neg_integer()) :: :ok

  @callback get_node_shared_key_index() :: non_neg_integer()
  @callback set_node_shared_secrets_key_index(non_neg_integer()) :: :ok

  @callback set_storage_nonce(binary()) :: :ok
  @callback get_storage_nonce() :: binary()
end
