defmodule ArchEthic.Election.StorageConstraintsTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ArchEthic.Election.StorageConstraints
  alias ArchEthic.P2P.Node

  doctest StorageConstraints

  describe "number_replicas_by_2log10" do
    property "should return the total number nodes before 143 nodes" do
      check all(
              average_availabilities <-
                StreamData.list_of(StreamData.float(min: 0.0, max: 1.0),
                  min_length: 1,
                  max_length: 143
                )
            ) do
        assert Enum.map(average_availabilities, fn avg ->
                 %Node{
                   first_public_key: :crypto.strong_rand_bytes(32),
                   last_public_key: :crypto.strong_rand_bytes(32),
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   average_availability: avg
                 }
               end)
               |> StorageConstraints.number_replicas_by_2log10() == length(average_availabilities)
      end
    end

    property "should return the less than total number nodes after 143 nodes" do
      check all(
              average_availabilities <-
                StreamData.list_of(StreamData.float(min: 0.0, max: 1.0), min_length: 143)
            ) do
        assert Enum.map(average_availabilities, fn avg ->
                 %Node{
                   first_public_key: :crypto.strong_rand_bytes(32),
                   last_public_key: :crypto.strong_rand_bytes(32),
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   average_availability: avg
                 }
               end)
               |> StorageConstraints.number_replicas_by_2log10() <= 143
      end
    end
  end
end
