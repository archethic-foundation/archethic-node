defmodule Archethic.Contracts.LoaderTest do
  use ArchethicCase

  alias Archethic.ContractRegistry
  alias Archethic.ContractSupervisor

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConstants
  alias Archethic.Contracts.Loader
  alias Archethic.Contracts.Worker

  alias Archethic.TransactionChain.Transaction

  alias Archethic.ContractFactory

  import Mox

  describe "load_transaction/1" do
    test "should create a supervised worker for the given transaction with contract code" do
      code = """
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

      tx =
        %Transaction{address: contract_address} =
        ContractFactory.create_valid_contract_tx(code, seed: "contract1_seed")

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
      code = """
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

      tx1 = ContractFactory.create_valid_contract_tx(code, seed: "contract2_seed")

      tx2 = ContractFactory.create_next_contract_tx(tx1, seed: "contract2_seed")

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
    code = """
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

    tx =
      %Transaction{address: contract_address} =
      ContractFactory.create_valid_contract_tx(code, seed: "contract3_seed")

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
