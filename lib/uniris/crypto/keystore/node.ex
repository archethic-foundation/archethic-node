defmodule Uniris.Crypto.NodeKeystore do
  @moduledoc false

  alias Uniris.Crypto
  alias Uniris.Crypto.NodeKeystoreImpl

  @behaviour NodeKeystoreImpl

  def child_spec(opts), do: impl().child_spec(opts)

  @impl NodeKeystoreImpl
  @spec sign_with_first_key(data :: binary()) :: binary()
  def sign_with_first_key(data) do
    impl().sign_with_first_key(data)
  end

  @impl NodeKeystoreImpl
  @spec sign_with_last_key(data :: binary()) :: binary()
  def sign_with_last_key(data) do
    impl().sign_with_last_key(data)
  end

  @impl NodeKeystoreImpl
  @spec last_public_key() :: Crypto.key()
  def last_public_key do
    impl().last_public_key()
  end

  @impl NodeKeystoreImpl
  @spec first_public_key() :: Crypto.key()
  def first_public_key do
    impl().first_public_key()
  end

  @impl NodeKeystoreImpl
  @spec next_public_key() :: Crypto.key()
  def next_public_key do
    impl().next_public_key()
  end

  @impl NodeKeystoreImpl
  @spec diffie_hellman(public_key :: Crypto.key()) :: binary()
  def diffie_hellman(public_key) do
    impl().diffie_hellman(public_key)
  end

  @impl NodeKeystoreImpl
  @spec persist_next_keypair() :: :ok
  def persist_next_keypair do
    impl().persist_next_keypair()
  end

  defp impl do
    Application.get_env(:uniris, __MODULE__) |> Keyword.fetch!(:impl)
  end
end
