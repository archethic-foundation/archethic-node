defmodule UnirisElection.DefaultImpl.HeuristicConstraintsTest do
  use ExUnit.Case
  alias UnirisElection.DefaultImpl.HeuristicConstraints
  doctest HeuristicConstraints
  use ExUnitProperties

  property "validation_number/1 should return 5 when less than 10 uco are transfered" do
    check(
      all(
        address <- StreamData.binary(length: 32),
        previous_public_key <- StreamData.binary(length: 32),
        previous_signature <- StreamData.binary(length: 64),
        origin_signature <- StreamData.binary(length: 64),
        transfers <-
          StreamData.fixed_map(%{
            to: StreamData.binary(length: 32),
            amount: StreamData.float(max: 10)
          })
      ) do
        HeuristicConstraints.validation_number(%UnirisChain.Transaction{
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
        }) == 5
      end
    )
  end

  property "validation_number/1 should return 5 when more than 10 uco are transfered" do
    check(
      all(
        address <- StreamData.binary(length: 32),
        previous_public_key <- StreamData.binary(length: 32),
        previous_signature <- StreamData.binary(length: 64),
        origin_signature <- StreamData.binary(length: 64),
        transfers <-
          StreamData.fixed_map(%{
            to: StreamData.binary(length: 32),
            amount: StreamData.float(min: 11)
          })
      ) do
        HeuristicConstraints.validation_number(%UnirisChain.Transaction{
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
        }) > 5
      end
    )
  end

  property "number_replicas/1 should returns a less number of nodes than the the list of nodes provided" do
    check all(
            nodes <-
              list_of(
                StreamData.fixed_map(%{
                  average_availability:
                    StreamData.frequency([
                      {3, StreamData.constant(1)},
                      {1, StreamData.float(min: 0, max: 1)}
                    ])
                }),
                min_length: 1
              )
          ) do
      nb_replicas = HeuristicConstraints.number_replicas(nodes)
      nb_nodes = length(nodes)
      assert nb_replicas <= nb_nodes
    end
  end
end
