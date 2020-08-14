defmodule Uniris.Governance.CommandLogger.Impl do
  @moduledoc false

  @callback write(data :: binary(), metadata :: Keyword.t()) :: :ok
end
