# defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.WebSocket do
#   @moduledoc """
#     Provides WebSOcket client To connect ArchEthicWeb.Endpoint
#   """
#   use WebSockex
#   # @default_ws_type "ws"
#   require Logger
#   def start_link(state, opts \\ []) do
#     # port = Keyword.get!(opts, :port)
#     # path = Keyword.get!(opts, :path)
#     # ws_type = Keyword.get(opts,:wss,"ws" )
#     WebSockex.start_link("localhost:4000/socket",__MODULE__, state ,opts)
#   end

#   def handle_frame(data,_state ) do
#   Logger.info("client says #{data}")

#   end
# end
