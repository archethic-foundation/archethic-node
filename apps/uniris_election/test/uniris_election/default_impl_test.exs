defmodule UnirisElection.DefaultImplTest do
  use ExUnit.Case
  use ExUnitProperties

  alias UnirisElection.DefaultImpl, as: Election

  setup do
    UnirisCrypto.set_daily_nonce("myseed")
    UnirisCrypto.set_storage_nonce("myseed")
    :ok
  end

  import Mox

  property "validation_nodes/1 should return more than 3 validation nodes in different are with 3 different locations" do
    check all(
            tx <- gen_transaction(),
            nodes <-
              uniq_list_of(
                StreamData.fixed_map(%{
                  last_public_key: StreamData.binary(length: 32),
                  availability: StreamData.constant(1),
                  geo_patch: StreamData.string(Enum.concat([?A..?F, ?0..?9]), length: 3),
                  authorized?: StreamData.constant(true)
                }),
                min_length: 5
              )
          ) do
      expect(MockP2P, :list_nodes, fn -> nodes end)
      validation_nodes = Election.validation_nodes(tx)
      assert length(validation_nodes) >= 3
      assert Enum.uniq_by(validation_nodes, & &1.geo_patch) >= 3
    end
  end

  property "storage_nodes/1 should return less than the number of nodes when its more than 200" do
    check all(
            address <- StreamData.binary(length: 32),
            nodes <-
              uniq_list_of(
                StreamData.fixed_map(%{
                  first_public_key: StreamData.binary(length: 32),
                  availability: StreamData.constant(1),
                  average_availability: StreamData.constant(1),
                  geo_patch:
                    StreamData.frequency([
                      {3, StreamData.constant("F3C")},
                      {2, StreamData.constant("A4C")},
                      {3, StreamData.constant("CC8")},
                      {1, StreamData.constant("BAD")}
                    ])
                }),
                min_length: 200
              )
          ) do
      expect(MockP2P, :list_nodes, fn -> nodes end)
      storage_nodes = Election.storage_nodes(address, false)
      assert length(storage_nodes) < length(nodes)
    end
  end

  property "storage_nodes/1 should all the nodes when the number of nodes is less than 200" do
    check all(
            address <- StreamData.binary(length: 32),
            nodes <-
              uniq_list_of(
                StreamData.fixed_map(%{
                  first_public_key: StreamData.binary(length: 32),
                  availability: StreamData.constant(1),
                  average_availability: StreamData.constant(1),
                  geo_patch:
                    StreamData.frequency([
                      {3, StreamData.constant("F3C")},
                      {2, StreamData.constant("A4C")},
                      {3, StreamData.constant("CC8")},
                      {1, StreamData.constant("BAD")}
                    ])
                }),
                min_length: 1,
                max_length: 200
              )
          ) do
      expect(MockP2P, :list_nodes, fn -> nodes end)
      storage_nodes = Election.storage_nodes(address, false)
      assert length(storage_nodes) == length(nodes)
    end
  end

  def gen_transaction do
    gen all(
          address <- StreamData.binary(length: 32),
          previous_public_key <- StreamData.binary(length: 32),
          previous_signature <- StreamData.binary(length: 64),
          origin_signature <- StreamData.binary(length: 64),
          transfers <-
            StreamData.fixed_map(%{
              to: StreamData.binary(length: 32),
              amount: StreamData.float()
            })
        ) do
      %UnirisChain.Transaction{
        address: address,
        type: :ledger,
        timestamp: DateTime.utc_now() |> DateTime.to_unix(),
        data: %UnirisChain.Transaction.Data{
          ledger: %UnirisChain.Transaction.Data.Ledger{
            uco: %UnirisChain.Transaction.Data.Ledger.UCO{
              transfers: transfers
            }
          }
        },
        previous_public_key: previous_public_key,
        previous_signature: previous_signature,
        origin_signature: origin_signature
      }
    end
  end
end
