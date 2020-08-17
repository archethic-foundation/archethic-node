defmodule Uniris.Governance.Testnet.Impl do
  @moduledoc false

  @callback deploy(
              address :: binary(),
              p2p_port :: :inet.port_number(),
              web_port :: :inet.port_number(),
              p2p_seeds :: binary()
            ) :: :ok
end
