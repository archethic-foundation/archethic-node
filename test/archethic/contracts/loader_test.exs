defmodule Archethic.Contracts.LoaderTest do
  use ArchethicCase

  alias Archethic.{Crypto, ContractRegistry, Contracts, TransactionChain, ContractSupervisor}
  alias Contracts.{Contract, ContractConstants, Loader, Worker}
  alias TransactionChain.{Transaction, TransactionData, Transaction.ValidationStamp}

  import Mox

  describe "load_transaction/1" do
    test "should create a supervised worker for the given transaction with contract code" do
      {pub0, _} = Crypto.derive_keypair("contract1_seed", 0)
      {pub1, _} = Crypto.derive_keypair("contract1_seed", 1)

      contract_address = Crypto.derive_address(pub1)

      tx = %Transaction{
        address: contract_address,
        data: %TransactionData{
          code: """
          condition transaction: [
            content: "hello"
          ]

          condition inherit: [
            content: "hi"
          ]

          actions triggered_by: transaction do
            set_content "hi"
          end
          """
        },
        previous_public_key: pub0,
        validation_stamp: %ValidationStamp{
          recipients: [],
          timestamp: DateTime.utc_now()
        }
      }

      assert :ok = Loader.load_transaction(tx, execute_contract?: false, io_transaction?: false)
      [{pid, _}] = Registry.lookup(ContractRegistry, contract_address)

      assert Enum.any?(
               DynamicSupervisor.which_children(ContractSupervisor),
               &match?({_, ^pid, :worker, [Worker]}, &1)
             )

      assert %{
               contract: %Contract{
                 triggers: %{
                   {:transaction, nil, nil} => _
                 },
                 constants: %ContractConstants{contract: %{"address" => ^contract_address}}
               }
             } = :sys.get_state(pid)
    end

    test "should stop a previous contract for the same chain" do
      {pub0, _} = Crypto.derive_keypair("contract2_seed", 0)
      {pub1, _} = Crypto.derive_keypair("contract2_seed", 1)
      {pub2, _} = Crypto.derive_keypair("contract2_seed", 2)

      tx1 = %Transaction{
        address: Crypto.derive_address(pub1),
        data: %TransactionData{
          code: """
          condition transaction: [
            content: "hello"
          ]

          condition inherit: [
            content: "hi"
          ]

          actions triggered_by: transaction do
            set_content "hi"
          end
          """
        },
        previous_public_key: pub0,
        validation_stamp: %ValidationStamp{
          recipients: [],
          timestamp: DateTime.utc_now()
        }
      }

      tx2 = %Transaction{
        address: Crypto.derive_address(pub2),
        data: %TransactionData{
          code: """
          condition transaction: [
            content: "hello"
          ]

          condition inherit: [
            content: "hi"
          ]

          actions triggered_by: transaction do
            set_content "hi2"
          end
          """
        },
        previous_public_key: pub1,
        validation_stamp: %ValidationStamp{
          recipients: [],
          timestamp: DateTime.utc_now()
        }
      }

      assert :ok = Loader.load_transaction(tx1, execute_contract?: false, io_transaction?: false)
      [{pid1, _}] = Registry.lookup(ContractRegistry, tx1.address)
      assert :ok = Loader.load_transaction(tx2, execute_contract?: false, io_transaction?: false)
      [{pid2, _}] = Registry.lookup(ContractRegistry, tx2.address)

      assert !Process.alive?(pid1)
      assert Process.alive?(pid2)

      assert Enum.any?(
               DynamicSupervisor.which_children(ContractSupervisor),
               &match?({_, ^pid2, :worker, [Worker]}, &1)
             )
    end
  end

  test "start_link/1 should load smart contract from DB" do
    {pub0, _} = Crypto.derive_keypair("contract3_seed", 0)
    {pub1, _} = Crypto.derive_keypair("contract3_seed", 1)

    contract_address = Crypto.derive_address(pub1)

    tx = %Transaction{
      address: contract_address,
      data: %TransactionData{
        code: """
        condition transaction: [
          content: "hello"
        ]

        condition inherit: [
          content: "hi"
        ]

        actions triggered_by: transaction do
          set_content "hi"
        end
        """
      },
      previous_public_key: pub0,
      validation_stamp: %ValidationStamp{
        recipients: [],
        timestamp: DateTime.utc_now()
      }
    }

    MockDB
    |> stub(:list_io_transactions, fn _ -> [] end)
    |> stub(:list_transactions, fn _ -> [tx] end)

    assert {:ok, _} = Loader.start_link()
    [{pid, _}] = Registry.lookup(ContractRegistry, contract_address)

    assert Enum.any?(
             DynamicSupervisor.which_children(ContractSupervisor),
             &match?({_, ^pid, :worker, [Worker]}, &1)
           )

    assert %{
             contract: %Contract{
               triggers: %{
                 {:transaction, nil, nil} => _
               },
               constants: %ContractConstants{contract: %{"address" => ^contract_address}}
             }
           } = :sys.get_state(pid)
  end
end
