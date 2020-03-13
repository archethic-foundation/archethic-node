defmodule UnirisSharedSecrets.DefaultImpl.StoreTest do
  use ExUnit.Case

  alias UnirisSharedSecrets.DefaultImpl.Store
  alias UnirisCrypto, as: Crypto

  test "add_origin_public_key/1 should update the list of origin public keys" do
    {pub, _} = Crypto.generate_deterministic_keypair("hello")
    Store.add_origin_public_key(:software, pub)
    Process.sleep(100)
    assert pub in Store.get_origin_public_keys()
  end

end
