defmodule Archethic.Contracts.LoaderTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.ContractRegistry
  alias Archethic.ContractSupervisor

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Loader
  alias Archethic.Contracts.Worker

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.NetworkView

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.UTXO

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1)
    })

    :ok
  end

  describe "load_transaction/1" do
    setup do
      start_supervised!(NetworkView)
      :ets.new(:archethic_worker_lock, [:set, :named_table, :public, read_concurrency: true])
      :ok
    end

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

      tx = ContractFactory.create_valid_contract_tx(code, seed: random_seed())

      genesis = Transaction.previous_address(tx)

      assert :ok = Loader.load_transaction(tx, genesis, execute_contract?: false)
      assert [{pid, _}] = Registry.lookup(ContractRegistry, genesis)

      assert Enum.any?(
               DynamicSupervisor.which_children(ContractSupervisor),
               &match?({_, ^pid, :worker, [Worker]}, &1)
             )

      assert {_, %{contract: %Contract{transaction: ^tx}, genesis_address: ^genesis}} =
               :sys.get_state(pid)
    end

    test "should update contract for the same chain" do
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

      tx1 = ContractFactory.create_valid_contract_tx(code, seed: random_seed())

      tx2 = ContractFactory.create_next_contract_tx(tx1, seed: random_seed())

      genesis = Transaction.previous_address(tx1)

      assert :ok = Loader.load_transaction(tx1, genesis, execute_contract?: false)
      [{pid, _}] = Registry.lookup(ContractRegistry, genesis)

      assert {_, %{contract: %Contract{transaction: ^tx1}, genesis_address: ^genesis}} =
               :sys.get_state(pid)

      assert :ok = Loader.load_transaction(tx2, genesis, execute_contract?: false)
      [{^pid, _}] = Registry.lookup(ContractRegistry, genesis)

      assert {_, %{contract: %Contract{transaction: ^tx2}, genesis_address: ^genesis}} =
               :sys.get_state(pid)
    end

    test "should execute contract if worker is unlocked" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("If you see this, I was unlocked")
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code, seed: random_seed())
      contract_genesis = Transaction.previous_address(contract_tx)

      :persistent_term.put(:archethic_up, :up)

      Loader.load_transaction(contract_tx, contract_genesis, execute_contract?: false)

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([],
          seed: random_seed(),
          recipients: [
            %Recipient{address: contract_genesis, action: "test", args: []}
          ]
        )

      trigger_genesis = Transaction.previous_address(trigger_tx)

      UTXO.load_transaction(trigger_tx, trigger_genesis)

      me = self()

      MockDB
      |> expect(:get_transaction, fn ^trigger_address, _, _ -> {:ok, trigger_tx} end)

      MockClient
      |> expect(:send_message, fn _, %StartMining{}, _ ->
        send(me, :transaction_sent)
        :ok
      end)

      Loader.load_transaction(trigger_tx, trigger_genesis, execute_contract?: true)

      assert_receive :transaction_sent
      :persistent_term.erase(:archethic_up)
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
      ContractFactory.create_valid_contract_tx(code, seed: random_seed())

    genesis = Transaction.previous_address(tx)

    MockDB
    |> expect(:list_genesis_addresses, fn -> [genesis] end)
    |> expect(:get_last_chain_address, fn ^genesis -> {contract_address, DateTime.utc_now()} end)
    |> expect(:get_transaction, fn ^contract_address, _, _ -> {:ok, tx} end)

    assert {:ok, _} = Loader.start_link()
    [{pid, _}] = Registry.lookup(ContractRegistry, genesis)

    assert Enum.any?(
             DynamicSupervisor.which_children(ContractSupervisor),
             &match?({_, ^pid, :worker, [Worker]}, &1)
           )

    assert {_, %{contract: %Contract{transaction: ^tx}, genesis_address: ^genesis}} =
             :sys.get_state(pid)
  end
end
