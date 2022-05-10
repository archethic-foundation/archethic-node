defmodule Archethic.Crypto.NodeKeystore.Origin do
  @moduledoc false

  use Knigge, otp_app: :archethic, delegate_at_runtime?: true

  alias Archethic.Crypto

  @callback child_spec(any) :: Supervisor.child_spec()
  @callback sign_with_origin_key(data :: iodata()) :: binary()
  @callback origin_public_key() :: Crypto.key()
end
