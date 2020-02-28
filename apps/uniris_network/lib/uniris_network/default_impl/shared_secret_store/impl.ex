defmodule UnirisNetwork.DefaultImpl.SharedSecretStore.Impl do
  @moduledoc false

  @callback storage_nonce() :: binary()

  @callback daily_nonce() :: binary()

  @callback origin_public_keys() :: list(UnirisCrypto.key())

  @callback set_daily_nonce(binary()) :: :ok

  @callback add_origin_public_key(UnirisCrypto.key()) :: :ok
end
