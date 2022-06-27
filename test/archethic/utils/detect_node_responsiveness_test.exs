defmodule Archethic.Utils.DetectNodeResponsivenessTest do
  use ArchethicCase

  alias Archethic.Utils.DetectNodeResponsiveness

  import Mox
  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Node

  test "start_link/2 for start state" do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    replaying_fn = fn count ->
      count
    end

    {:ok, pid} = DetectNodeResponsiveness.start_link(address, replaying_fn)
    assert true == Process.alive?(pid)
  end

  test "start_link/2 for hard timeout state" do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    # dummy replaying fn with count as argument
    replaying_fn = fn count ->
      count
    end

    {:ok, pid} = DetectNodeResponsiveness.start_link(address, replaying_fn)
    Process.sleep(11_000)
    assert false == Process.alive?(pid)
  end

  test "start_link/2 for soft timeout state" do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    me = self()

    replaying_fn = fn count ->
      send(me, :replay)
      count
    end

    {pub1, _} = Crypto.derive_keypair("node1", 0)
    {pub2, _} = Crypto.derive_keypair("node2", 0)
    {pub3, _} = Crypto.derive_keypair("node3", 0)
    {pub4, _} = Crypto.derive_keypair("node4", 0)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      authorized?: true,
      last_public_key: pub1,
      first_public_key: pub1,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now(),
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: pub2,
      last_public_key: pub2,
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      enrollment_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: pub3,
      last_public_key: pub3,
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      enrollment_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: pub4,
      last_public_key: pub4,
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      enrollment_date: DateTime.utc_now()
    })

    {:ok, pid} = DetectNodeResponsiveness.start_link(address, replaying_fn)

    MockDB
    |> stub(:transaction_exists?, fn ^address ->
      false
    end)

    #  first soft_timeout
    assert true == Process.alive?(pid)
    Process.sleep(10_500)
    assert_received :replay
    # second soft_timeout
    Process.sleep(10_500)
    assert_received :replay
    assert true == Process.alive?(pid)
    # third soft_timeout
    Process.sleep(10_500)
    assert_received :replay
    assert true == Process.alive?(pid)
    # last timeout leading to stop as hard_timeout
    Process.sleep(10_500)
    assert false == Process.alive?(pid)
  end

  test "check to first soft_timeout" do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    me = self()

    replaying_fn = fn count ->
      send(me, :replay)
      count
    end

    {pub1, _} = Crypto.derive_keypair("node1", 0)
    {pub2, _} = Crypto.derive_keypair("node2", 0)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      authorized?: true,
      last_public_key: pub1,
      first_public_key: pub1,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now(),
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: pub2,
      last_public_key: pub2,
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      enrollment_date: DateTime.utc_now()
    })

    {:ok, pid} = DetectNodeResponsiveness.start_link(address, replaying_fn)

    MockDB
    |> stub(:transaction_exists?, fn ^address ->
      true
    end)

    #  first soft_timeout
    assert true == Process.alive?(pid)
    Process.sleep(10_500)
    assert false == Process.alive?(pid)
    # assert_received :replay
  end

  test "check to second soft_timeout" do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    me = self()

    replaying_fn = fn count ->
      send(me, :replay)
      count
    end

    {pub1, _} = Crypto.derive_keypair("node1", 0)
    {pub2, _} = Crypto.derive_keypair("node2", 0)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      authorized?: true,
      last_public_key: pub1,
      first_public_key: pub1,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now(),
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: pub2,
      last_public_key: pub2,
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      enrollment_date: DateTime.utc_now()
    })

    {:ok, pid} = DetectNodeResponsiveness.start_link(address, replaying_fn)

    MockDB
    |> expect(:transaction_exists?, fn ^address ->
      false
    end)
    |> expect(:transaction_exists?, fn ^address ->
      true
    end)

    #  first soft_timeout
    assert true == Process.alive?(pid)
    Process.sleep(10_500)
    assert true == Process.alive?(pid)
    assert_received :replay

    Process.sleep(10_500)
    assert false == Process.alive?(pid)
  end

  test "check to all timeouts" do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    me = self()

    replaying_fn = fn count ->
      send(me, :replay)
      count
    end

    {pub1, _} = Crypto.derive_keypair("node1", 0)
    {pub2, _} = Crypto.derive_keypair("node2", 0)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      authorized?: true,
      last_public_key: pub1,
      first_public_key: pub1,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now(),
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: pub2,
      last_public_key: pub2,
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      enrollment_date: DateTime.utc_now()
    })

    {:ok, pid} = DetectNodeResponsiveness.start_link(address, replaying_fn)

    MockDB
    |> stub(:transaction_exists?, fn ^address ->
      false
    end)

    #  After first soft_timeout it goes to hard_timeout
    assert true == Process.alive?(pid)
    Process.sleep(10_500)
    assert true == Process.alive?(pid)
    assert_received :replay

    Process.sleep(10_500)
    assert false == Process.alive?(pid)
  end
end
