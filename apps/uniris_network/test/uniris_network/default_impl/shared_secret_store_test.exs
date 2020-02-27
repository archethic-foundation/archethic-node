defmodule UnirisNetwork.DefaultImpl.SharedSecretStoreTest do
  use ExUnit.Case

  alias UnirisNetwork.DefaultImpl.SharedSecretStore

  setup do
    :ets.insert(:shared_secrets, {:storage_nonce, :crypto.strong_rand_bytes(32)})
    :ets.insert(:shared_secrets, {:daily_nonce, :crypto.strong_rand_bytes(32)})

    pub = UnirisCrypto.generate_random_keypair()
    :ets.insert(:shared_secrets, {:origin_public_keys, [pub]})
    :ok
  end

  test "storage_nonce/0 should return a binary nonce" do
    assert <<_::binary>> = SharedSecretStore.storage_nonce()
  end

  test "daily_nonce/0 should return a binary nonce" do
    assert <<_::binary>> = SharedSecretStore.daily_nonce()
  end

  test "set_daily_nonce/1 should update the daily nonce" do
    SharedSecretStore.set_daily_nonce("mynewnonce")
    assert "mynewnonce" = SharedSecretStore.daily_nonce
  end

  test "add_origin_public_key/1 should update the list of origin public keys" do
    pub = UnirisCrypto.generate_random_keypair()
    SharedSecretStore.add_origin_public_key(pub)
    assert 2 == length(SharedSecretStore.origin_public_keys())
  end
 
end
