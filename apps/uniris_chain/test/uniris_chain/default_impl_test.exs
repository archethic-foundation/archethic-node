defmodule UnirisChain.DefaultImplTest do
  use ExUnit.Case

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisChain.TransactionSupervisor
  alias UnirisChain.DefaultImpl, as: Chain
  alias UnirisChain.DefaultImpl.Store
  alias UnirisChain.TransactionRegistry
  alias UnirisChain.TransactionSupervisor
  alias UnirisCrypto, as: Crypto

  setup do
    DynamicSupervisor.which_children(TransactionSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(TransactionSupervisor, pid)
    end)

    Crypto.add_origin_seed("origin_seed")

    :ets.delete_all_objects(:ko_transactions)

    :ok
  end

  test "store_transaction/1 should create a process for the transaction and store it" do
    tx = Transaction.from_node_seed(:transfer)
    Chain.store_transaction(tx)

    [{:undefined, pid, _, [Transaction]}] =
      DynamicSupervisor.which_children(TransactionSupervisor)

    assert tx == :sys.get_state(pid)

    {:ok, stored_tx} = Store.get_transaction(tx.address)
    assert tx == stored_tx
  end

  test "store_transaction_chain/1 should create a process for the last transaction and store the chain" do
    chain = [
      Transaction.from_node_seed(:transfer),
      Transaction.from_node_seed(:transfer, %Transaction.Data{}, 1)
    ]

    Chain.store_transaction_chain(chain)

    [{:undefined, pid, _, [Transaction]}] =
      DynamicSupervisor.which_children(TransactionSupervisor)

    assert List.first(chain) == :sys.get_state(pid)

    {:ok, stored_chain} = Store.get_transaction_chain(List.first(chain).address)
    assert chain == stored_chain
  end

  test "store_ko_transaction/1 should persist it on ETS table" do
    tx = Transaction.from_seed("other_seed", :transfer)

    tx =
      Map.put(tx, :validation_stamp, %ValidationStamp{
        proof_of_work: "",
        proof_of_integrity: "",
        ledger_movements: %LedgerMovements{},
        node_movements: %NodeMovements{fee: 0, rewards: []},
        signature: ""
      })

    :ok = Chain.store_ko_transaction(tx)
    assert [{_, _}] = :ets.lookup(:ko_transactions, tx.address)
  end

  test "get_transaction/1 should retrieve the transaction in memory first" do
    tx = Transaction.from_node_seed(:transfer)
    Chain.store_transaction(tx)
    {:ok, mem_tx} = Chain.get_transaction(tx.address)
    assert mem_tx == tx
  end

  test "get_transaction/1 should retrieve the transaction in storage if not in memory" do
    tx = Transaction.from_node_seed(:transfer)
    Store.store_transaction(tx)
    {:ok, stored_tx} = Chain.get_transaction(tx.address)
    assert [] == DynamicSupervisor.which_children(TransactionSupervisor)
    assert stored_tx == tx
  end

  test "get_transaction/1 should return an error when the transaction is ko" do
    tx = Transaction.from_node_seed(:transfer)

    tx =
      Map.put(tx, :validation_stamp, %ValidationStamp{
        proof_of_work: "",
        proof_of_integrity: "",
        ledger_movements: %LedgerMovements{},
        node_movements: %NodeMovements{fee: 0, rewards: []},
        signature: ""
      })

    Chain.store_ko_transaction(tx)
    assert {:error, :invalid_transaction} = Chain.get_transaction(tx.address)
  end

  test "get_transaction_chain/1 should retrieve the transaction chain from the storage" do
    chain = [
      Transaction.from_node_seed(:transfer),
      Transaction.from_node_seed(:transfer, %Transaction.Data{}, 1)
    ]

    Chain.store_transaction_chain(chain)

    {:ok, stored_chain} = Chain.get_transaction_chain(List.first(chain).address)

    assert chain == stored_chain
  end

  test "get_last_node_shared_secrets_transaction/0 should retrieve the last node shared secret transaction in memory first" do
    tx = Transaction.from_node_seed(:node_shared_secrets)
    Chain.store_transaction(tx)
    {:ok, shared_tx} = Chain.get_last_node_shared_secrets_transaction()
    assert shared_tx == tx
  end

  test "get_last_node_shared_secrets_transaction/0 should retrieve the last node shared secret transaction in storage if not in memory" do
    tx = Transaction.from_node_seed(:node_shared_secrets)
    Store.store_transaction(tx)
    {:ok, shared_tx} = Chain.get_last_node_shared_secrets_transaction()
    assert shared_tx == tx
  end
end
