defmodule UnirisNetwork.P2P.Client.Impl do
  @moduledoc false

  alias UnirisNetwork.Node

  @callback send(Node.t(), request :: binary()) ::
              {:ok, term(), Node.t()} | {:error, :network_issue}
end
