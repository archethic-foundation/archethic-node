defmodule Archethic.UTXO.LoaderTest do
  use ArchethicCase

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.UTXO.Loader
  alias Archethic.UTXO.MemoryLedger

  alias Archethic.TransactionFactory

  import ArchethicCase

  setup do
    PartitionSupervisor.start_link(
      child_spec: Loader,
      name: Archethic.UTXO.LoaderSupervisor,
      partitions: 1
    )

    :ok
  end

  import Mox

  describe "add_utxo/2" do
    test "should write the unspent output into memory and file ledger" do
      utxo = %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        protocol_version: current_protocol_version()
      }

      me = self()

      MockUTXOLedger
      |> stub(:append, fn genesis, utxo ->
        send(me, {:append, genesis, utxo})
      end)

      Loader.add_utxo(utxo, "@Alice0")

      assert [^utxo] = MemoryLedger.get_unspent_outputs("@Alice0")
      assert_receive {:append, "@Alice0", ^utxo}
    end
  end

  describe "consume_inputs/2" do
    test "should consumed inputs and flush the new unspent outputs into memory and file ledger" do
      utxo = %UnspentOutput{
        from: random_address(),
        type: :UCO,
        amount: 100_000_000,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      tx =
        %Transaction{
          validation_stamp: %ValidationStamp{
            genesis_address: genesis,
            ledger_operations: %LedgerOperations{unspent_outputs: unspent_outputs}
          }
        } = TransactionFactory.create_valid_transaction([utxo])

      v_unspent_outputs =
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

      MockUTXOLedger
      |> expect(:flush, fn ^genesis, ^v_unspent_outputs -> :ok end)

      Loader.consume_inputs(tx)

      assert ^v_unspent_outputs = MemoryLedger.get_unspent_outputs(genesis)
    end

    test "should consumed inputs and flush after memory threshold" do
      {:ok, agent_pid} = Agent.start_link(fn -> [] end)

      uco_utxos =
        Enum.map(1..5, fn _ ->
          %UnspentOutput{
            from: random_address(),
            type: :UCO,
            amount: 100_000_000,
            timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
          }
        end)

      token_utxos =
        Enum.map(1..5, fn _ ->
          %UnspentOutput{
            from: random_address(),
            type: {:token, random_address(), 0},
            amount: 100_000_000,
            timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
          }
        end)

      utxos = Enum.concat(uco_utxos, token_utxos)
      v_utxos = VersionedUnspentOutput.wrap_unspent_outputs(utxos, current_protocol_version())

      tx =
        %Transaction{
          validation_stamp: %ValidationStamp{
            genesis_address: genesis_address,
            ledger_operations: %LedgerOperations{unspent_outputs: unspent_outputs}
          }
        } = TransactionFactory.create_valid_transaction(utxos)

      assert Enum.all?(unspent_outputs, &(&1.type == :UCO))

      new_unspent_output =
        token_utxos
        |> Enum.concat(unspent_outputs)
        |> VersionedUnspentOutput.wrap_unspent_outputs(current_protocol_version())

      MockUTXOLedger
      |> stub(:append, fn _genesis, utxo -> Agent.update(agent_pid, &(&1 ++ [utxo])) end)
      |> stub(:stream, fn _ -> Agent.get(agent_pid, & &1) end)
      |> expect(:flush, fn ^genesis_address, ^new_unspent_output -> :ok end)

      Enum.each(v_utxos, fn utxo -> Loader.add_utxo(utxo, genesis_address) end)

      assert [] == MemoryLedger.get_unspent_outputs(genesis_address)
      assert v_utxos == Agent.get(agent_pid, & &1)

      Loader.consume_inputs(tx)
    end
  end
end
