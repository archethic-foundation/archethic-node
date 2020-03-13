defmodule UnirisSharedSecrets.DefaultImpl do
  @moduledoc false

  alias __MODULE__.Store

  @behaviour UnirisSharedSecrets.Impl

  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisP2P, as: P2P

  defdelegate child_spec(opts), to: Store

  @impl true
  @spec origin_public_keys(:all | UnirisSharedSecrets.origin_family()) :: list(UnirisCrypto.key())
  def origin_public_keys(:all) do
    Store.get_origin_public_keys()
  end

  def origin_public_keys(family) do
    Store.get_origin_public_keys(family)
  end

  @impl true
  @spec add_origin_public_key(
          family :: :software | :usb | :biometric,
          public_key :: Crypto.key()
        ) :: :ok
  def add_origin_public_key(family, public_key) do
    Store.add_origin_public_key(family, public_key)
  end

  @impl true
  @spec new_shared_secrets_transaction(binary()) :: Transaction.pending()
  def new_shared_secrets_transaction(transaction_seed) do
    daily_nonce_seed = :crypto.strong_rand_bytes(32)
    {daily_nonce_public_key, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)

    aes_key = :crypto.strong_rand_bytes(32)

    encrypted_keys =
      Enum.reduce(P2P.list_nodes(), %{}, fn n, acc ->
        encrypted_key = Crypto.ec_encrypt(aes_key, n.last_public_key)
        Map.put(acc, n.last_public_key, encrypted_key)
      end)

    {origin_key_seeds, origin_public_keys} = create_origin_keys()

    storage_nonce_seed = :crypto.strong_rand_bytes(32)
    {storage_nonce_public_key, _} = Crypto.generate_deterministic_keypair(storage_nonce_seed)

    create_shared_secret_transaction(
      transaction_seed,
      {daily_nonce_seed, daily_nonce_public_key},
      {storage_nonce_seed, storage_nonce_public_key},
      {origin_key_seeds, origin_public_keys},
      aes_key,
      encrypted_keys
    )
  end

  defp create_origin_keys() do
    origin_keys_seeds = Enum.map(0..9, fn _ -> :crypto.strong_rand_bytes(32) end)

    origin_public_keys =
      Enum.map(origin_keys_seeds, fn seed ->
        Crypto.add_origin_seed(seed)
        {pub, _pv} = Crypto.generate_deterministic_keypair(seed)
        add_origin_public_key(:software, pub)
        pub
      end)

    {origin_keys_seeds, origin_public_keys}
  end

  defp create_shared_secret_transaction(
         transaction_seed,
         {daily_nonce_seed, daily_nonce_public_key},
         {storage_nonce_seed, storage_nonce_public},
         {origin_keys_seeds, origin_public_keys},
         aes_key,
         encrypted_keys
       ) do
    Transaction.from_seed(transaction_seed, :node_shared_secrets, %Data{
      content: """
      daily_nonce_public: #{daily_nonce_public_key |> Base.encode16()}
      storage_nonce_public: #{storage_nonce_public |> Base.encode16()}
      origin_public_keys: #{origin_public_keys |> Enum.map(&Base.encode16/1) |> Enum.join(",")}
      """,
      keys: %{
        secret:
          %{
            transaction_seed: transaction_seed,
            daily_nonce_seed: daily_nonce_seed,
            storage_nonce_seed: storage_nonce_seed,
            origin_keys_seeds: origin_keys_seeds
          }
          |> Crypto.aes_encrypt(aes_key),
        authorized_keys: encrypted_keys
      }
    })
  end
end
