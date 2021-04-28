defmodule Uniris.Crypto.NodeKeystoreImpl do
  @moduledoc false

  alias Uniris.Crypto

  @callback sign_with_node_key(data :: binary()) :: binary()
  @callback sign_with_node_key(data :: binary(), index :: non_neg_integer()) :: binary()

  @callback node_public_key() :: Crypto.key()
  @callback node_public_key(index :: number()) :: Crypto.key()

  @callback diffie_hellman(public_key :: Crypto.key()) :: binary()
end
