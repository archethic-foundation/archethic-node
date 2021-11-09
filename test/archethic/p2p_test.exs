defmodule ArchEthic.P2PTest do
  use ArchEthicCase

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  doctest ArchEthic.P2P

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  test "get_node_info/0 should return retrieve local node information" do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key()
    })

    Process.sleep(100)

    assert %Node{ip: {127, 0, 0, 1}} = P2P.get_node_info()
  end

  describe "duplicating_node?/3" do
    test "should return true for duplicate node" do
      MockDB
      |> stub(:get_first_public_key, fn _ ->
        <<1::16, 1::8>>
      end)

      assert P2P.duplicating_node?(
               {127, 0, 0, 1},
               3000,
               <<1::16, 1::8>>,
               [
                 %Node{
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   first_public_key: <<0::16, 0::8>>
                 }
               ]
             )
    end

    test "should return false for original node" do
      MockDB
      |> stub(:get_first_public_key, fn _ ->
        <<1::16, 1::8>>
      end)

      refute P2P.duplicating_node?(
               {127, 0, 0, 1},
               3000,
               <<1::16, 1::8>>,
               [
                 %Node{
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   first_public_key: <<1::16, 1::8>>
                 }
               ]
             )
    end

    test "should return false for node with different ip/port" do
      MockDB
      |> stub(:get_first_public_key, fn _ ->
        <<1::16, 1::8>>
      end)

      refute P2P.duplicating_node?(
               {127, 0, 0, 2},
               3000,
               <<1::16, 1::8>>,
               [
                 %Node{
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   first_public_key: <<1::16, 1::8>>
                 }
               ]
             )

      refute P2P.duplicating_node?(
               {127, 0, 0, 1},
               3001,
               <<1::16, 1::8>>,
               [
                 %Node{
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   first_public_key: <<1::16, 1::8>>
                 }
               ]
             )
    end
  end
end
