defmodule UnirisElection.DefaultImplTest do
  use ExUnit.Case
  use ExUnitProperties

  alias UnirisElection.DefaultImpl, as: Election

  property "validation_nodes/3 should return an error when the number of nodes is too less" do
    check all(
            address <- StreamData.binary(length: 32),
            previous_public_key <- StreamData.binary(length: 32),
            previous_signature <- StreamData.binary(length: 64),
            origin_signature <- StreamData.binary(length: 64),
            transfers <-
              StreamData.fixed_map(%{
                to: StreamData.binary(length: 32),
                amount: StreamData.float()
              }),
            nodes <-
              uniq_list_of(
                StreamData.fixed_map(%{
                  last_public_key: StreamData.binary(length: 32),
                  availability:
                    StreamData.frequency([
                      {90, StreamData.constant(0)},
                      {1, StreamData.constant(1)}
                    ]),
                  geo_patch: StreamData.string(Enum.concat([?A..?F, ?0..?9]), length: 3)
                }),
                min_length: 5
              ),
            nonce <- StreamData.binary(length: 32)
          ) do
      tx = %UnirisChain.Transaction{
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

      assert {:error, :unsufficient_network} ==
               Election.validation_nodes(tx, nodes, nonce)
    end
  end
end
