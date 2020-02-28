defmodule UnirisP2P.MessageTest do
  use ExUnit.Case
  use ExUnitProperties

  doctest UnirisP2P.Message

  alias UnirisP2P.Message
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisCrypto, as: Crypto
  alias UnirisNetwork.Node
  alias UnirisValidation

  import Mox

  setup :verify_on_exit!

  test "encode/1 should return an encoded payload" do
    check all(payload <- StreamData.term()) do
      encoded_payload = Message.encode(payload)
      assert match?(<<_::binary-33, _::binary-64, _::binary>>, encoded_payload)
    end
  end

  test "decode/1 should return the decoded payload when is it valid" do
    check all(payload <- StreamData.term()) do
      encoded_payload = Message.encode(payload)
      assert match?({:ok, _, <<_::binary-33>>}, Message.decode(encoded_payload))
    end
  end

  test "decode/1 should return an error when the decoded data is malformed" do
    check all(encoded_payload <- StreamData.term()) do
      assert match?({:error, :invalid_payload}, Message.decode(encoded_payload))
    end
  end

  test "process/2 should failed when the message is unexpected" do
    assert {:error, :invalid_message} = Message.process(:fake_message, "me")
  end

  test "process/2 with message `{:start_validation, _, _, _}` should failed when welcome node public key is invalid" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    {:error, :invalid_welcome_node} =
      Message.process(
        {:start_validation, tx, "welcome_node_public_key", ["validator_public_key"]},
        Crypto.last_node_public_key()
      )
  end

  test "process/2 with message `{:start_validation, _, _, _}` should failed with invalid validation node public keys" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    MockNetwork
    |> stub(:node_info, fn key ->
      case Enum.filter([{Crypto.last_node_public_key(), self()}], fn {k, _} -> key == k end) do
        [{_, _}] ->
          :ok
      end
    end)

    {:error, :invalid_validation_nodes} =
      Message.process(
        {:start_validation, tx, Crypto.last_node_public_key(), ["validator_public_key"]},
        Crypto.last_node_public_key()
      )
  end

  test "process/2 with {:replicate_transaction, _} should failed if the message is not coming from a validatio node" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: "",
      validation_stamp: %ValidationStamp{
        proof_of_work: "",
        proof_of_integrity: "",
        ledger_movements: %LedgerMovements{},
        node_movements: %NodeMovements{fee: 0.1, rewards: []},
        signature: ""
      },
      cross_validation_stamps: [{"", []}]
    }

    MockElection
    |> expect(:validation_nodes, fn _, _, _, _ -> [] end)

    MockNetwork
    |> expect(:list_nodes, fn -> [] end)
    |> expect(:daily_nonce, fn -> "" end)

    assert {:error, :unauthorized} =
             Message.process({:replicate_transaction, tx}, "node_public_key")
  end

  test "process/2 with {:cross_validate, _, _} message should failed when the from is not the coordinator of the transaction " do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    stamp = %ValidationStamp{
      proof_of_work: "",
      proof_of_integrity: "",
      ledger_movements: %LedgerMovements{},
      node_movements: %NodeMovements{fee: 0.1, rewards: []},
      signature: ""
    }

    MockNetwork
    |> expect(:list_nodes, fn -> [] end)
    |> expect(:daily_nonce, fn -> "" end)

    MockElection
    |> expect(:validation_nodes, fn _, _, _, _ ->
      [
        %Node{
          first_public_key: "coordinator",
          last_public_key: "coordinator",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "validator_node",
          last_public_key: "validator_node",
          ip: {127, 0, 0, 1},
          port: 3000
        }
      ]
    end)

    MockValidation
    |> expect(:mining?, fn _ -> true end)
    |> expect(:mined_transaction, fn _ -> tx end)

    assert {:error, :unauthorized} = Message.process({:cross_validate, tx.address, stamp}, "public_key")
  end

  test "process/2 with {:cross_validation_done, _, _} message should failed when the from is not the a coordinator node of the transaction " do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    stamp = %ValidationStamp{
      proof_of_work: "",
      proof_of_integrity: "",
      ledger_movements: %LedgerMovements{},
      node_movements: %NodeMovements{fee: 0.1, rewards: []},
      signature: ""
    }

    MockNetwork
    |> expect(:list_nodes, fn -> [] end)
    |> expect(:daily_nonce, fn -> "" end)

    MockElection
    |> expect(:validation_nodes, fn _, _, _, _ ->
      [
        %Node{
          first_public_key: "coordinator",
          last_public_key: "coordinator",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "public_key",
          last_public_key: "public_key",
          ip: {127, 0, 0, 1},
          port: 3000
        }
      ]
    end)

    MockValidation
    |> expect(:mining?, fn _ -> true end)
    |> expect(:mined_transaction, fn _ -> tx end)

    assert {:error, :unauthorized} = Message.process({:cross_validation_done, tx.address, {"", []}}, "coordinator")
  end
end
