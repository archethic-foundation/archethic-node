defmodule Uniris.Crypto.NodeKeystoreImpl do
  @moduledoc false

  alias Uniris.Crypto

  @callback sign_with_first_key(data :: binary()) :: binary()
  @callback sign_with_last_key(data :: binary()) :: binary()

  @callback last_public_key() :: Crypto.key()
  @callback first_public_key() :: Crypto.key()
  @callback next_public_key() :: Crypto.key()

  @callback diffie_hellman(public_key :: Crypto.key()) :: binary()

  @callback persist_next_keypair() :: :ok
end
