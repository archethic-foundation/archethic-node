# defmodule Migration_1_5_6 do
#   @moduledoc false

#   alias Archethic.Crypto
#   alias Archethic.P2P
#   alias Archethic.P2P.Node

#   alias Archethic.TransactionChain
#   alias Archethic.TransactionChain.Transaction
#   alias Archethic.TransactionChain.TransactionData

#   alias Archethic.Utils

#   require Logger

#   def run() do
#     %Node{ip: ip, port: p2p_port, http_port: http_port, transport: transport, reward_address: reward_address, origin_public_key: origin_public_key} = P2P.get_node_info()

#     mining_public_key = Crypto.mining_node_public_key()
#     key_certificate = Crypto.get_key_certificate(origin_public_key)

#     genesis_address = Crypto.first_node_public_key() |> Crypto.derive_address()
#     {:ok, %Transaction{data: %TransactionData{code: code}}} =
#       TransactionChain.get_last_transaction(genesis_address, data: [:code])

#     tx =
#       Transaction.new(:node, %TransactionData{
#         code: code,
#         content:
#           Node.encode_transaction_content(
#             ip,
#             p2p_port,
#             http_port,
#             transport,
#             reward_address,
#             origin_public_key,
#             key_certificate,
#             mining_public_key
#           )
#       })

#       :ok = Archethic.send_new_transaction(tx, forward?: true)

#       nodes =
#         P2P.authorized_and_available_nodes()
#         |> Enum.filter(&P2P.node_connected?/1)
#         |> P2P.nearest_nodes()

#       case Utils.await_confirmation(tx.address, nodes) do
#         {:ok, _} ->
#           Logger.info("Mining node updated")

#         {:error, reason} ->
#           Logger.warning("Cannot update node transaction - #{inspect reason}")
#       end
#   end
# end
