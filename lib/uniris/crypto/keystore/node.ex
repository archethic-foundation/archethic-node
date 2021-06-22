defmodule Uniris.Crypto.NodeKeystore do
  @moduledoc false

  alias Uniris.Crypto

  use Knigge, otp_app: :uniris

  @callback child_spec(any) :: Supervisor.child_spec()

  @callback sign_with_first_key(data :: binary()) :: binary()
  @callback sign_with_last_key(data :: binary()) :: binary()
  @callback sign_with_previous_key(data :: binary()) :: binary()

  @callback last_public_key() :: Crypto.key()
  @callback first_public_key() :: Crypto.key()
  @callback next_public_key() :: Crypto.key()
  @callback previous_public_key() :: Crypto.key()

  @callback diffie_hellman(public_key :: Crypto.key()) :: binary()

  @callback persist_next_keypair() :: :ok
end
