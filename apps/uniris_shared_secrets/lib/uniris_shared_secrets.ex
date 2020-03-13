defmodule UnirisSharedSecrets do
  @behaviour __MODULE__.Impl

  @doc false
  defdelegate child_spec(opts), to: __MODULE__.DefaultImpl

  @type origin_family :: :software | :usb | :biometric

  @doc """
  Retrieve the origin public keys used to determine the proof of work.
  """
  @impl true
  @spec origin_public_keys(:all | origin_family()) :: list(UnirisCrypto.key())
  def origin_public_keys(family) when family in [:all, :software, :usb, :biometric] do
    impl().origin_public_keys(family)
  end

  @doc """
  Add a new origin public key by giving its family: biometric, software, usb

  Family can be used in the smart contract to provide a level of security
  """
  @impl true
  @spec add_origin_public_key(
          family :: origin_family(),
          public_key :: UnirisCrypto.key()
        ) :: :ok
  def add_origin_public_key(family, public_key) when family in [:software, :usb, :biometric] do
    impl().add_origin_public_key(family, public_key)
  end

  @doc """
  Create the new node shared keys including chain seed, daily nonce, storage nonce and origin keys
  """
  @impl true
  @spec new_shared_secrets_transaction(seed :: binary()) :: UnirisChain.Transaction.pending()
  def new_shared_secrets_transaction(seed) do
    impl().new_shared_secrets_transaction(seed)
  end

  defp impl() do
    Application.get_env(:uniris_shared_secrets, :impl, __MODULE__.DefaultImpl)
  end
end
