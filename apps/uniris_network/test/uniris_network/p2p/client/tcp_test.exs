defmodule UnirisNetwork.P2P.Client.TCPTest do
  use ExUnit.Case

  alias UnirisNetwork.Node
  alias UnirisNetwork.P2P.Client.TCPImpl, as: TCPClient
  alias UnirisNetwork.P2P.Request

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  test "send/2 should success when the host is reachable" do

    MockRequest
    |> expect(:get_transaction, fn address -> "get_transaction_#{address}" end)
    |> expect(:execute, fn _ -> {:ok, %{}} end)

    request = Request.get_transaction("0123345678")

    {:ok, pub} = UnirisCrypto.generate_random_keypair()

    response = TCPClient.send(%Node{ip: "127.0.0.1", port: Application.get_env(:uniris_network, :port), last_public_key: pub, first_public_key: pub, availability: 1, average_availability: 1, geo_patch: "AA0"}, request)

    assert match? {:ok, {:ok, _data}, _node} , response
  end

  test "send/2 should return an network issue when the node is not reachable" do

    MockRequest
    |> expect(:get_transaction, fn address -> "get_transaction_#{address}" end)

    {:ok, pub} = UnirisCrypto.generate_random_keypair()


    request = Request.get_transaction("0123345678")
    response = TCPClient.send(%Node{ip: "174.192.172.32", port: 80, last_public_key: pub, first_public_key: pub, availability: 1, average_availability: 1, geo_patch: "AA0"}, request)
    

    assert match? {:error, :network_issue}, response

    
  end
end
  
