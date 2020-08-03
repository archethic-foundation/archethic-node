defmodule Uniris.Mining.BinarySequenceTest do
  use ExUnit.Case

  alias Uniris.Mining.BinarySequence
  alias Uniris.P2P.Node

  test "from_subset/2 create binary sequence from a list and a subset and mark the subset with 1" do
    list = [
      %Node{ip: {127, 0, 0, 1}, port: 3000, first_public_key: "key1", last_public_key: "key1"},
      %Node{ip: {127, 0, 0, 1}, port: 3000, first_public_key: "key2", last_public_key: "key2"},
      %Node{ip: {127, 0, 0, 1}, port: 3000, first_public_key: "key3", last_public_key: "key3"}
    ]

    subset = [
      %Node{ip: {127, 0, 0, 1}, port: 3000, first_public_key: "key1", last_public_key: "key1"},
      %Node{ip: {127, 0, 0, 1}, port: 3000, first_public_key: "key3", last_public_key: "key3"}
    ]

    assert <<1::1, 0::1, 1::1>> = BinarySequence.from_subset(list, subset)
  end

  test "from_availability/1 create binary sequence from a list and mark with availability with 1" do
    list = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        available?: true
      },
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key2",
        last_public_key: "key2",
        available?: false
      },
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true
      }
    ]

    assert <<1::1, 0::1, 1::1>> = BinarySequence.from_availability(list)
  end

  test "aggregate/2 execute merge two binary sequence into one" do
    first = <<1::1, 0::1, 1::1, 1::1>>
    second = <<0::1, 0::1, 1::1, 0::1>>
    assert <<1::1, 0::1, 1::1, 1::1>> = BinarySequence.aggregate(first, second)
  end

  test "extract/1 represents a binary sequence into an array of 1 and 0" do
    assert [1, 0, 1] = BinarySequence.extract(<<1::1, 0::1, 1::1>>)
  end
end
