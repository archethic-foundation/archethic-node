defmodule Uniris.Crypto.NodeKeystore do
  @moduledoc false

  alias Uniris.Crypto
  alias Uniris.Crypto.NodeKeystoreImpl

  @behaviour NodeKeystoreImpl

  def child_spec(opts), do: impl().child_spec(opts)

  @impl NodeKeystoreImpl
  @spec sign_with_node_key(data :: binary()) :: binary()
  def sign_with_node_key(data) do
    impl().sign_with_node_key(data)
  end

  @impl NodeKeystoreImpl
  @spec sign_with_node_key(data :: binary(), index :: non_neg_integer()) :: binary()
  def sign_with_node_key(data, index) do
    impl().sign_with_node_key(data, index)
  end

  @impl NodeKeystoreImpl
  @spec node_public_key() :: Crypto.key()
  def node_public_key do
    impl().node_public_key()
  end

  @impl NodeKeystoreImpl
  @spec node_public_key(index :: number()) :: Crypto.key()
  def node_public_key(index) do
    impl().node_public_key(index)
  end

  @impl NodeKeystoreImpl
  @spec diffie_hellman(public_key :: Crypto.key()) :: binary()
  def diffie_hellman(public_key) do
    impl().diffie_hellman(public_key)
  end

  defp impl do
    Application.get_env(:uniris, __MODULE__) |> Keyword.fetch!(:impl)
  end
end
