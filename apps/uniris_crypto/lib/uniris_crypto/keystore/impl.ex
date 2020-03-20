defmodule UnirisCrypto.Keystore.Impl do
  @moduledoc false

  @callback sign_with_node_key(data :: binary()) :: binary()
  @callback sign_with_node_key(data :: binary(), index :: number()) :: binary()
  @callback sign_with_origin_key(data :: binary()) :: binary()
  @callback origin_public_keys() :: list(UnirisCrypto.key())
  @callback hash_with_daily_nonce(data :: binary()) :: binary()
  @callback hash_with_storage_nonce(data :: binary()) :: binary()
  @callback add_origin_seed(seed :: binary()) :: :ok
  @callback set_daily_nonce(seed :: binary()) :: :ok
  @callback set_storage_nonce(seed :: binary()) :: :ok
  @callback node_public_key() :: UnirisCrypto.key()
  @callback node_public_key(index :: number()) :: UnirisCyrpto.key()
  @callback increment_number_of_generate_node_keys() :: :ok
  @callback decrypt_with_node_key!(binary()) :: :ok
  @callback derivate_beacon_chain_address(subset :: binary(), date :: non_neg_integer()) :: UnirisCrypto.key()

end
