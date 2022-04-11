# defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.ImitateSockets do
#   @moduledoc """
#     SOcket endpoint To connect ArchEthicWeb.Endpoint
#   """
#   use Genserver

#   def start_link(opts) do
#     GenServer.start_link(__MODULE__, opts)
#   end

#   def init(opts) do
#     addr =
#     Keyword.get(opts, :host)
#     |> to_charlist()
#     |>:inet.getaddr(:inet)
#     port = Keyword.get(opts, :port)
#     public_key = Keyword.get(opts, :public_key)
#     private_key = Keyword.get(opts, :private_key)

#     {:ok, socket} = :gen_tcp.connect(addr, port, [:binary, active: true, packet: 4])

#     {:ok,
#      %{
#        socket: socket,
#        messages: %{},
#        request_id: 0,
#        public_key: public_key,
#        private_key: private_key
#      }}
#   end
# end
