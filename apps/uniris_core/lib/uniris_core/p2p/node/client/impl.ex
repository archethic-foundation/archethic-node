defmodule UnirisCore.P2P.NodeClientImpl do
  @moduledoc false

  @callback start_link(Node.t()) :: {:ok, pid()}
  @callback send_message(public_key :: UnirisCore.Crypto.key(), message :: term()) :: term()
end
