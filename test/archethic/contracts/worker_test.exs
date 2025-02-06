defmodule Archethic.Contracts.WorkerTest do
  use ArchethicCase

  alias Archethic.ContractRegistry
  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.PubSub

  alias Archethic.ContractSupervisor
  alias Archethic.Contracts.Interpreter.Contract
  alias Archethic.Contracts.Worker

  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.UnspentOutputList

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  alias Archethic.UTXO

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

  import ArchethicCase
  import Mox
  import Mock

  def load_send_tx_constraints() do
    setup_before_send_tx()
  end

  setup do
    load_send_tx_constraints()

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    MockDB
    |> stub(:chain_size, fn _ -> 1 end)

    MockClient
    |> stub(:send_message, fn _, %GetUnspentOutputs{}, _ ->
      {:ok, %UnspentOutputList{unspent_outputs: []}}
    end)

    transaction_seed = :crypto.strong_rand_bytes(32)

    {first_pub, _} = Crypto.derive_keypair(transaction_seed, 1)
    contract_address = Crypto.derive_address(first_pub)

    {next_pub, _} = Crypto.derive_keypair(transaction_seed, 2)
    next_address = Crypto.derive_address(next_pub)

    to = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

    expected_tx = %Transaction{
      address: next_address,
      type: :transfer,
      data: %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: [
              %Transfer{
                to: to,
                amount: 1_040_000_000
              }
            ]
          }
        }
      }
    }

    on_exit(fn ->
      Supervisor.which_children(ContractSupervisor)
      |> Enum.each(fn {_, pid, _, _} ->
        DynamicSupervisor.terminate_child(ContractSupervisor, pid)
      end)
    end)

    {:ok,
     %{
       seed: transaction_seed,
       contract_address: contract_address,
       expected_tx: expected_tx,
       to: to
     }}
  end

  describe "start_link/1" do
    test "should spawn a process accessible by its genesis address", %{seed: seed} do
      code = """
      @version 1
      condition transaction: []
      """

      contract =
        ContractFactory.create_valid_contract_tx(code, seed: seed) |> Contract.from_transaction!()

      genesis = Transaction.previous_address(contract.transaction)

      {:ok, pid} = Worker.start_link(contract: contract, genesis_address: genesis)
      assert Process.alive?(pid)
      assert {_, %{contract: ^contract}} = :sys.get_state(pid)

      assert [{^pid, _}] = Registry.lookup(ContractRegistry, genesis)
    end

    test "should schedule a timer for a an datetime trigger", %{
      seed: seed,
      expected_tx: expected_tx,
      to: to
    } do
      address = Base.encode16(to)

      code = """
      condition inherit: [
        uco_transfers: %{ "#{address}" => 1_040_000_000}
      ]

      actions triggered_by: datetime, at: #{DateTime.utc_now() |> DateTime.add(1) |> DateTime.to_unix()} do
        set_type transfer
        add_uco_transfer to: "#{address}", amount: 1_040_000_000
      end
      """

      contract =
        ContractFactory.create_valid_contract_tx(code, seed: seed) |> Contract.from_transaction!()

      genesis = Transaction.previous_address(contract.transaction)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn tx, _ ->
          assert tx.address == expected_tx.address
          assert tx.data.code == code
          send(me, :transaction_sent)
          :ok
        end
      ) do
        {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: genesis)
        assert_receive :transaction_sent, 3000
      end
    end

    test "should schedule a timer for a an interval trigger", %{
      seed: seed,
      expected_tx: expected_tx,
      to: to
    } do
      address = Base.encode16(to)

      code = """
      condition inherit: [
        uco_transfers: %{ "#{address}" => 1_040_000_000}
      ]

      actions triggered_by: interval, at: "* * * * * *" do
        set_type transfer
        add_uco_transfer to: "#{address}", amount: 1_040_000_000
      end
      """

      contract =
        ContractFactory.create_valid_contract_tx(code, seed: seed) |> Contract.from_transaction!()

      genesis = Transaction.previous_address(contract.transaction)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn tx, _ ->
          assert tx.address == expected_tx.address
          assert tx.data.code == code
          send(me, :transaction_sent)
          :ok
        end
      ) do
        {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: genesis)
        assert_receive :transaction_sent, 2000
        # Transaction has been replicated so we set new contract
        Worker.set_contract(genesis, contract, true)
        assert_receive :transaction_sent, 2000
      end
    end

    test "should not execute next call if node is not up" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("If you see this, I was unlocked")
        end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: contract_genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: random_seed())

      contract = Contract.from_transaction!(contract_tx)

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([],
          seed: random_seed(),
          recipients: [
            %Recipient{address: contract_genesis, action: "test", args: []}
          ],
          version: 3
        )

      me = self()

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> expect(:get_transaction, 0, fn ^trigger_address, _, _ -> {:ok, trigger_tx} end)

      UTXO.load_transaction(trigger_tx)

      MockClient
      |> stub(:send_message, fn _, %StartMining{}, _ ->
        send(me, :transaction_sent)
        :ok
      end)

      :persistent_term.erase(:archethic_up)

      {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: contract_genesis)

      refute_receive :transaction_sent
    end

    test "should execute next call if node is up" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("If you see this, I was unlocked")
        end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: contract_genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: random_seed())

      contract = Contract.from_transaction!(contract_tx)

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([],
          seed: random_seed(),
          recipients: [%Recipient{address: contract_genesis, action: "test", args: []}],
          version: 3
        )

      me = self()

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> stub(:get_transaction, fn
        ^trigger_address, _, _ ->
          {:ok, trigger_tx}

        "nss_last_address", _, _ ->
          {:ok, %Transaction{validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}}}
      end)

      UTXO.load_transaction(trigger_tx)

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn _, _ ->
          send(me, :transaction_sent)
          :ok
        end
      ) do
        :persistent_term.put(:archethic_up, :up)

        {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: contract_genesis)

        assert_receive :transaction_sent

        :persistent_term.erase(:archethic_up)
      end
    end

    test "should not execute contract if transaction is loaded from self repair" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("You should not see this")
        end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: contract_genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: random_seed())

      contract = Contract.from_transaction!(contract_tx)

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([],
          seed: random_seed(),
          recipients: [
            %Recipient{address: contract_genesis, action: "test", args: []}
          ],
          version: 3
        )

      me = self()

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> stub(:get_transaction, fn
        ^trigger_address, _, _ ->
          {:ok, trigger_tx}

        "nss_last_address", _, _ ->
          {:ok, %Transaction{validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}}}
      end)

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn _, _ ->
          send(me, :transaction_sent)
          :ok
        end
      ) do
        :persistent_term.put(:archethic_up, :up)

        {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: contract_genesis)

        UTXO.load_transaction(trigger_tx)

        refute_receive :transaction_sent

        Worker.set_contract(contract_genesis, contract, false)

        refute_receive :transaction_sent

        Worker.set_contract(contract_genesis, contract, true)

        assert_receive :transaction_sent

        :persistent_term.erase(:archethic_up)
      end
    end

    test "should execute next call when node becomes up" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("If you see this, I was unlocked")
        end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: contract_genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: random_seed())

      contract = Contract.from_transaction!(contract_tx)

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([],
          seed: random_seed(),
          recipients: [
            %Recipient{address: contract_genesis, action: "test", args: []}
          ],
          version: 3
        )

      me = self()

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> stub(:get_transaction, fn
        ^trigger_address, _, _ ->
          {:ok, trigger_tx}

        "nss_last_address", _, _ ->
          {:ok, %Transaction{validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}}}
      end)

      UTXO.load_transaction(trigger_tx)

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn _, _ ->
          send(me, :transaction_sent)
          :ok
        end
      ) do
        :persistent_term.erase(:archethic_up)

        {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: contract_genesis)

        refute_receive :transaction_sent

        PubSub.notify_node_status(:node_up)

        assert_receive :transaction_sent
      end
    end
  end

  describe "process_next_trigger/1" do
    test "should not execute when no transaction trigger has been defined", %{seed: seed} do
      code = """
      @version 1
      condition transaction: []
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: seed)

      contract = Contract.from_transaction!(contract_tx)

      {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: genesis)

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([],
          recipients: [%Recipient{address: genesis}],
          version: 3
        )

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> expect(:get_transaction, fn ^trigger_address, _, _ -> {:ok, trigger_tx} end)

      UTXO.load_transaction(trigger_tx)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn _, _ ->
          send(me, :transaction_sent)
          :ok
        end
      ) do
        Worker.process_next_trigger(genesis)
        refute_receive :transaction_sent
      end
    end

    test "should execute a transaction trigger code using an incoming transaction", %{
      seed: seed,
      expected_tx: expected_tx,
      to: to
    } do
      address = Base.encode16(to)

      code = """
      condition inherit: [
        uco_transfers: %{ "#{address}" => 1_040_000_000}
      ]

      condition transaction: []

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to:  "#{address}", amount: 1_040_000_000
      end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: seed)

      contract = Contract.from_transaction!(contract_tx)

      {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: genesis)

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([],
          recipients: [%Recipient{address: genesis}],
          version: 3
        )

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> expect(:get_transaction, fn ^trigger_address, _, _ -> {:ok, trigger_tx} end)

      UTXO.load_transaction(trigger_tx)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn tx, _ ->
          assert tx.address == expected_tx.address
          assert tx.data.ledger == expected_tx.data.ledger
          assert tx.data.code == code
          send(me, :transaction_sent)
          :ok
        end
      ) do
        Worker.process_next_trigger(genesis)
        assert_receive :transaction_sent
      end
    end

    test "should return a different code if set in the smart contract code", %{
      seed: seed,
      expected_tx: expected_tx,
      to: to
    } do
      address = Base.encode16(to)

      code = ~s"""
      condition transaction: []

      condition inherit: [
        uco_transfers: %{ "#{address}" => 1_040_000_000}
      ]

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: "#{address}", amount: 1_040_000_000
        set_code "
          condition transaction: []

          condition inherit: [
            uco_transfers: %{ \\"#{address}\\" => 9_200_000_000}
          ]

          actions triggered_by: transaction do
            set_type transfer
            add_uco_transfer to: \\"#{address}\\", amount: 9_200_000_000
          end"
      end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: seed)

      contract = Contract.from_transaction!(contract_tx)

      {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: genesis)

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([],
          recipients: [%Recipient{address: genesis}],
          content: "Mr.X",
          version: 3
        )

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> expect(:get_transaction, fn ^trigger_address, _, _ -> {:ok, trigger_tx} end)

      UTXO.load_transaction(trigger_tx)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn tx, _ ->
          assert tx.address == expected_tx.address
          assert tx.data.ledger == expected_tx.data.ledger
          assert tx.data.code == "
    condition transaction: []

    condition inherit: [
      uco_transfers: %{ \"#{address}\" => 9_200_000_000}
    ]

    actions triggered_by: transaction do
      set_type transfer
      add_uco_transfer to: \"#{address}\", amount: 9_200_000_000
    end"
          send(me, :transaction_sent)
          :ok
        end
      ) do
        Worker.process_next_trigger(genesis)
        assert_receive :transaction_sent
      end
    end

    test "should execute actions based on an oracle trigger", %{seed: seed} do
      code = ~S"""
      condition oracle: [
        content: json_path_extract("$.uco.eur") > 0.20
      ]

      condition inherit: [
        content: regex_match?("(price increased).([0-9]+.[0-9]+)")
      ]

      actions triggered_by: oracle do
        uco_price = json_path_extract(transaction.content, "$.uco.eur")
        set_content "price increased #{uco_price}"
        set_type hosting
      end
      """

      oracle_tx =
        %Transaction{address: oracle_address} =
        TransactionFactory.create_valid_transaction([],
          type: :oracle,
          content: Jason.encode!(%{"uco" => %{"eur" => 0.21}})
        )

      MockDB
      |> expect(:get_transaction, fn ^oracle_address, _, _ -> {:ok, oracle_tx} end)

      contract =
        ContractFactory.create_valid_contract_tx(code, seed: seed) |> Contract.from_transaction!()

      genesis = Transaction.previous_address(contract.transaction)
      {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: genesis)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn tx, _ ->
          assert %Transaction{data: %TransactionData{content: "price increased 0.21"}} = tx
          send(me, :transaction_sent)
          :ok
        end
      ) do
        PubSub.notify_new_transaction(oracle_address, :oracle, DateTime.utc_now())
        assert_receive :transaction_sent
      end
    end

    test "ICO crowdsale", %{seed: seed, contract_address: contract_address} do
      code = """

      # Ensure the next transaction will be a transfer
      condition inherit: [
        type: transfer,
        token_transfers: size() == 1
        # TODO: to provide more security, we should check the destination address is within the previous transaction inputs
      ]

      # Define conditions to accept incoming transactions
      condition transaction: [
        type: transfer,
        uco_transfers: size() > 0
      ]

      actions triggered_by: transaction do
        # Get the amount of uco send to this contract
        amount_send = transaction.uco_transfers[contract.address]

        if amount_send > 0 do
          # Convert UCO to the number of tokens to credit. Each UCO worth 10000 token
          token_to_credit = amount_send * 10000

          # Send the new transaction
          set_type transfer
          add_token_transfer to: transaction.address, token_address: contract.address, amount: token_to_credit
        end
      end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: seed)

      contract = Contract.from_transaction!(contract_tx)

      {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: genesis)

      ledger = %Ledger{
        uco: %UCOLedger{transfers: [%Transfer{to: contract_address, amount: 100_000_000}]}
      }

      recipient = %Recipient{address: genesis}

      trigger_tx =
        %Transaction{address: trigger_tx_address} =
        TransactionFactory.create_valid_transaction([],
          ledger: ledger,
          recipients: [recipient],
          version: 3
        )

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> expect(:get_transaction, fn ^trigger_tx_address, _, _ -> {:ok, trigger_tx} end)

      UTXO.load_transaction(trigger_tx)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn tx, _ ->
          %Transaction{
            data: %TransactionData{
              ledger: %Ledger{token: %TokenLedger{transfers: token_transfers}}
            }
          } = tx

          assert [
                   %TokenTransfer{
                     amount: 1_000_000_000_000,
                     to: ^trigger_tx_address,
                     token_address: ^contract_address,
                     token_id: 0
                   }
                 ] = token_transfers

          send(me, :transaction_sent)
          :ok
        end
      ) do
        Worker.process_next_trigger(genesis)
        assert_receive :transaction_sent
      end
    end

    test "named action", %{seed: seed} do
      code = """
      @version 1

      condition triggered_by: transaction, on: vote(candidate), as: []
      actions triggered_by: transaction, on: vote(candidate) do
        Contract.set_content(candidate)
      end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: seed)

      contract = Contract.from_transaction!(contract_tx)

      {:ok, _pid} = Worker.start_link(contract: contract, genesis_address: genesis)

      recipient = %Recipient{address: genesis, action: "vote", args: ["Ms. Smith"]}

      trigger_tx =
        %Transaction{address: trigger_tx_address} =
        TransactionFactory.create_valid_transaction([],
          type: :data,
          recipients: [recipient],
          version: 3
        )

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> expect(:get_transaction, fn ^trigger_tx_address, _, _ -> {:ok, trigger_tx} end)

      UTXO.load_transaction(trigger_tx)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn tx, _ ->
          assert tx.data.content == "Ms. Smith"
          send(me, :transaction_sent)
          :ok
        end
      ) do
        Worker.process_next_trigger(genesis)
        assert_receive :transaction_sent
      end
    end

    test "should not crash the worker if contract code crashes", %{
      seed: seed,
      contract_address: contract_address
    } do
      code = """
      @version 1
      condition triggered_by: transaction, as: []
      actions triggered_by: transaction do
        n = 10 / 0
        Contract.set_content n
      end
      """

      contract_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis}} =
        ContractFactory.create_valid_contract_tx(code, seed: seed)

      contract = Contract.from_transaction!(contract_tx)

      {:ok, worker_pid} = Worker.start_link(contract: contract, genesis_address: genesis)

      ledger = %Ledger{
        uco: %UCOLedger{transfers: [%Transfer{to: contract_address, amount: 100_000_000}]}
      }

      recipient = %Recipient{address: genesis}

      trigger_tx =
        %Transaction{address: trigger_tx_address} =
        TransactionFactory.create_valid_transaction([],
          ledger: ledger,
          recipients: [recipient],
          version: 3
        )

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> expect(:get_transaction, fn ^trigger_tx_address, _, _ -> {:ok, trigger_tx} end)

      UTXO.load_transaction(trigger_tx)

      Worker.process_next_trigger(genesis)

      Process.sleep(100)

      assert Process.alive?(worker_pid)
    end
  end

  describe "Invalidate call" do
    test "should invalidate a call if it cannot be processed and process it after contract update" do
      code1 = """
      @version 1
      condition triggered_by: transaction, as: []
      actions triggered_by: transaction do
        n = 10 / String.to_number(transaction.content)
        Contract.set_content n
      end
      """

      code2 = """
      @version 1
      condition triggered_by: transaction, as: []
      actions triggered_by: transaction do
        if transaction.content == "0" do
          Contract.set_content("Invalid content")
        else
          n = 10 / String.to_number(transaction.content)
          Contract.set_content n
        end
      end
      """

      seed1 = random_seed()
      contract1_tx_address = Crypto.derive_keypair(seed1, 2) |> elem(0) |> Crypto.derive_address()

      contract1_tx =
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis}} =
        ContractFactory.create_valid_contract_tx(code1, seed: seed1)

      contract1 = Contract.from_transaction!(contract1_tx)

      contract2 =
        ContractFactory.create_valid_contract_tx(code2, seed: random_seed())
        |> Contract.from_transaction!()

      {:ok, _} = Worker.start_link(contract: contract1, genesis_address: genesis)

      recipient = %Recipient{address: genesis}

      invalid_trigger_tx =
        %Transaction{address: invalid_trigger_tx_address} =
        TransactionFactory.create_valid_transaction([],
          content: "0",
          recipients: [recipient],
          seed: random_seed(),
          version: 3
        )

      valid_trigger_tx =
        %Transaction{address: valid_trigger_tx_address} =
        TransactionFactory.create_valid_transaction([],
          content: "2",
          recipients: [recipient],
          seed: random_seed(),
          version: 3
        )

      MockDB
      |> stub(:get_last_chain_address, fn address -> {address, DateTime.utc_now()} end)
      |> expect(:get_transaction, fn ^invalid_trigger_tx_address, _, _ ->
        {:ok, invalid_trigger_tx}
      end)
      |> expect(:get_transaction, fn ^valid_trigger_tx_address, _, _ ->
        {:ok, valid_trigger_tx}
      end)
      |> expect(:get_transaction, fn ^invalid_trigger_tx_address, _, _ ->
        {:ok, invalid_trigger_tx}
      end)

      UTXO.load_transaction(invalid_trigger_tx)

      me = self()

      with_mock(Archethic, [:passthrough],
        send_new_transaction: fn tx, _ ->
          if tx.address == contract1_tx_address do
            assert tx.data.content == "5"

            # Remove call as it has been consumed
            utxo =
              genesis
              |> UTXO.stream_unspent_outputs()
              |> Enum.find(&(&1.unspent_output.from == valid_trigger_tx_address))
              |> VersionedUnspentOutput.unwrap_unspent_output()

            UTXO.MemoryLedger.remove_consumed_inputs(genesis, [utxo])
            send(me, :transaction_valid_sent)
          else
            assert tx.data.content == "Invalid content"
            send(me, :transaction_invalid_sent)
          end

          :ok
        end
      ) do
        Worker.process_next_trigger(genesis)
        refute_receive :transaction_sent
        UTXO.load_transaction(valid_trigger_tx)
        Worker.process_next_trigger(genesis)
        assert_receive :transaction_valid_sent
        Worker.set_contract(genesis, contract2, true)
        assert_receive :transaction_invalid_sent
      end
    end
  end
end
