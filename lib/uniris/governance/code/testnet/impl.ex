defmodule Uniris.Governance.Code.TestNetImpl do
  @moduledoc false

  @callback deploy(
              address :: binary(),
              p2p_port :: :inet.port_number(),
              web_port :: :inet.port_number(),
              p2p_seeds :: binary()
            ) :: :ok

  @callback clean(address :: binary()) :: :ok
end
