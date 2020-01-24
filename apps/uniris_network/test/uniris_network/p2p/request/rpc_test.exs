defmodule UnirisNetwork.P2P.Request.RPCTest do
  use ExUnit.Case

  alias UnirisNetwork.P2P.Request.RPCImpl, as: RPC
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp

  test "get_transaction/1 should return a command encoded with ETF" do
    command = RPC.get_transaction("0123345678")
    assert {:get_transaction, address: "0123345678"} == :erlang.binary_to_term(command, [:safe])
  end

  test "get_transaction_chain/1 should return a command encoded with ETF" do
    command = RPC.get_transaction_chain("0123345678")

    assert {:get_transaction_chain, address: "0123345678"} ==
             :erlang.binary_to_term(command, [:safe])
  end

  test "get_transaction_and_utxo/1 should return a command encoded with ETF" do
    command = RPC.get_transaction_and_utxo("0123345678")

    assert {:get_transaction_and_utxo, address: "0123345678"} ==
             :erlang.binary_to_term(command, [:safe])
  end

  test "prepare_validation/3 should return a command encoded with ETF" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      origin_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer
    }

    command = RPC.prepare_validation(tx, ["key1", "key2"], "key3")

    assert {:prepare_validation,
            transaction: tx,
            validation_node_public_keys: ["key1", "key2"],
            welcome_node_public_key: "key3"} == :erlang.binary_to_term(command, [:safe])
  end

  test "cross_validate_stamp/2 should return a command encoded with ETF" do
    command =
      RPC.cross_validate_stamp("0123345678", %ValidationStamp{
        proof_of_work: "",
        proof_of_integrity: "",
        signature: ""
      })

    assert {:cross_validate_stamp,
            transaction_address: "0123345678",
            validation_stamp: %ValidationStamp{
              proof_of_work: "",
              proof_of_integrity: "",
              signature: ""
            }} == :erlang.binary_to_term(command, [:safe])
  end

  test "store_transaction/1 should return a command encoded with ETF" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      origin_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer
    }

    command = RPC.store_transaction(tx)
    assert {:store_transaction, transaction: tx} == :erlang.binary_to_term(command, [:safe])
  end
end
