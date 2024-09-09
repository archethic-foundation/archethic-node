defmodule Archethic.Crypto.NodeKeystore do
  @moduledoc false

  alias Archethic.Crypto
  alias __MODULE__.Origin

  use Knigge, otp_app: :archethic, delegate_at_runtime?: true, default: __MODULE__.SoftwareImpl

  @callback child_spec(any) :: Supervisor.child_spec()

  @callback first_public_key() :: Crypto.key()
  @callback last_public_key() :: Crypto.key()
  @callback previous_public_key() :: Crypto.key()
  @callback next_public_key() :: Crypto.key()

  @callback set_node_key_index(index :: non_neg_integer()) :: :ok

  @callback persist_next_keypair() :: :ok

  @callback sign_with_first_key(data :: iodata()) :: binary()
  @callback sign_with_last_key(data :: iodata()) :: binary()
  @callback sign_with_previous_key(data :: iodata()) :: binary()

  @callback diffie_hellman_with_first_key(Crypto.key()) :: binary()
  @callback diffie_hellman_with_last_key(Crypto.key()) :: binary()

  @spec origin_public_key() :: Crypto.key()
  defdelegate origin_public_key, to: Origin

  @spec sign_with_origin_key(iodata()) :: binary()
  defdelegate sign_with_origin_key(data), to: Origin

  @callback sign_with_mining_key(iodata()) :: binary()
  @callback mining_public_key() :: binary()
end
