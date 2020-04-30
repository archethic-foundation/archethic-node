defmodule UnirisCore.SharedSecrets do
  alias __MODULE__.Cache
  alias UnirisCore.Crypto
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Keys

  @type origin_family :: :software | :usb | :biometric

  @type origin_shared_secrets_options :: [
          transaction_seed: binary()
        ]

  @origin_families [:software, :usb, :biometric]

  @doc """
  Retrieve the origin public keys for a given family
  """
  @spec origin_public_keys(origin_family()) :: list(UnirisCore.Crypto.key())
  def origin_public_keys(family) when family in @origin_families do
    Cache.origin_public_keys(family)
  end

  @doc """
  Retrieve all origin public keys across the families
  """
  @spec origin_public_keys() :: list(UnirisCrypto.key())
  def origin_public_keys() do
    Cache.origin_public_keys()
  end

  @doc """
  Add a new origin public key by giving its family: biometric, software, usb

  Family can be used in the smart contract to provide a level of security
  """
  @spec add_origin_public_key(
          family :: origin_family(),
          public_key :: UnirisCore.Crypto.key()
        ) :: :ok
  def add_origin_public_key(family, public_key)
      when family in @origin_families and is_binary(public_key) do
    Cache.add_origin_public_key(family, public_key)
  end

  @doc """
  Create the new node shared keys using the transaction seed located in the Crypto keystore and
  renew daily nonce with potiential storage nonce and origin software keys
  """
  @spec new_node_shared_secrets_transaction(
          authorized_node_public_keys :: list(UnirisCore.Crypto.key()),
          daily_nonce_seed :: binary(),
          aes_key :: binary()
        ) :: UnirisCore.Transaction.pending()
  def new_node_shared_secrets_transaction(
        authorized_node_public_keys,
        daily_nonce_seed,
        aes_key
      )
      when is_list(authorized_node_public_keys) and is_binary(daily_nonce_seed) and
             is_binary(aes_key) do
    Transaction.new(
      :node_shared_secrets,
      create_node_shared_secrets_data(daily_nonce_seed, aes_key, authorized_node_public_keys)
    )
  end

  defp create_node_shared_secrets_data(daily_nonce_seed, aes_key, authorized_public_keys) do
    {daily_nonce_public_key, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)

    secret =
      Crypto.aes_encrypt(daily_nonce_seed, aes_key) <>
        Crypto.encrypt_node_shared_secrets_transaction_seed(aes_key)

    %TransactionData{
      content: stringify_content(%{daily_nonce_public_key: daily_nonce_public_key}),
      keys: Keys.new(authorized_public_keys, aes_key, secret)
    }
  end

  defp stringify_content(content) when is_map(content) do
    content
    |> Enum.reduce([], fn {key, value}, acc ->
      ["#{Atom.to_string(key)}: #{stringify_content_value(value)}" | acc]
    end)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp stringify_content_value(value) when is_binary(value) do
    Base.encode16(value)
  end

  defp stringify_content_value(value) when is_list(value) do
    if Keyword.keyword?(value) do
      keyword_str =
        Enum.reduce(value, [], fn {key, value}, acc ->
          ["#{Atom.to_string(key)}: #{stringify_content_value(value)}" | acc]
        end)
        |> Enum.reverse()
        |> Enum.join(", ")

      "[" <> keyword_str <> "]"
    else
      Enum.reduce(value, [], fn val, acc ->
        [stringify_content_value(val) | acc]
      end)
      |> Enum.reverse()
      |> Enum.join(",")
    end
  end
end
