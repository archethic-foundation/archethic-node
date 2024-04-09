defmodule Archethic.P2P.Message.ReplicationErrorTest do
  @moduledoc false
  use ExUnit.Case
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message
  doctest Archethic.P2P.Message.ReplicationError

  test "Message.encode()/1  Message.decode()/1  " do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    Enum.each(list_error(), fn reason ->
      msg = %ReplicationError{
        address: address,
        reason: reason
      }

      assert msg == msg |> Message.encode() |> Message.decode() |> elem(0)
    end)
  end

  def list_error() do
    [
      :invalid_atomic_commitment,
      :invalid_node_election,
      :invalid_proof_of_work,
      :invalid_transaction_fee,
      :invalid_transaction_movements,
      :insufficient_funds,
      :invalid_chain,
      :invalid_transaction_with_inconsistencies,
      :invalid_pending_transaction,
      :invalid_inherit_constraints,
      :invalid_validation_stamp_signature,
      :invalid_unspent_outputs
    ]
  end
end
