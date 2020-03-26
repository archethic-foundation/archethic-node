defmodule UnirisSharedSecrets.Impl do
  @moduledoc false

  @callback origin_public_keys(UnirisSharedSecrets.origin_family()) :: list(UnirisCrypto.key())
  @callback add_origin_public_key(
              family :: :all | UnirisSharedSecrets.origin_family(),
              public_key :: UnirisCrypto.key()
            ) :: :ok
  @callback new_shared_secrets_transaction(seed :: binary(), list(binary())) :: UnirisChain.Transaction.pending()
end
