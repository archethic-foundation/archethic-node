defmodule Uniris.DB.CassandraImpl.CQLTest do
  use ExUnit.Case

  alias Uniris.DB.CassandraImpl.CQL

  describe "list_to_cql/1" do
    test "should stringify simple level of list of cql select" do
      fields = [
        :address,
        :previous_public_key,
        :timestamp
      ]

      assert [
               "address",
               "previous_public_key",
               "timestamp"
             ] = CQL.list_to_cql(fields) |> String.split(",")
    end

    test "should return * when not fields to project" do
      assert ["*"] = CQL.list_to_cql([]) |> String.split(",")
    end

    test "should stringify a nested list of cql select" do
      fields = [
        :address,
        :previous_public_key,
        validation_stamp: [
          ledger_operations: [:unspent_outputs, :node_movements, :transaction_movements]
        ]
      ]

      assert [
               "address",
               "previous_public_key",
               "validation_stamp.ledger_operations.unspent_outputs",
               "validation_stamp.ledger_operations.node_movements",
               "validation_stamp.ledger_operations.transaction_movements"
             ] = CQL.list_to_cql(fields) |> String.split(",")
    end
  end
end
