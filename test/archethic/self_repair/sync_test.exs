defmodule ArchEthic.SelfRepair.SyncTest do
  use ArchEthicCase, async: false

  alias ArchEthic.BeaconChain.Slot.TransactionSummary
  alias ArchEthic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary
  alias ArchEthic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetBeaconSummary
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetTransactionInputs
  alias ArchEthic.P2P.Message.TransactionInputList
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionFactory

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionInput

  alias ArchEthic.SharedSecrets.MemTables.NetworkLookup

  alias ArchEthic.SelfRepair.Sync

  alias ArchEthic.Utils

  import Mox

  describe "last_sync_date/0" do
    test "should get nil if not last sync file and not prior nodes" do
      assert Sync.last_sync_date() == nil
    end

    test "should get the last sync date from the stored filed file" do
      file =
        Application.get_env(:archethic, Sync)
        |> Keyword.fetch!(:last_sync_file)
        |> Utils.mut_dir()

      last_sync_date = DateTime.utc_now() |> DateTime.add(-60) |> Utils.truncate_datetime()

      new_sync_date = last_sync_date |> DateTime.to_unix() |> Integer.to_string()
      Path.dirname(file) |> File.mkdir_p!()
      :ok = File.write!(file, new_sync_date, [:write])

      assert Sync.last_sync_date() == last_sync_date
    end
  end

  test "store_last_sync_date/1 should store the last sync date into the last sync file" do
    last_sync_date = DateTime.utc_now() |> DateTime.add(-60) |> Utils.truncate_datetime()
    :ok = Sync.store_last_sync_date(last_sync_date)
    assert Sync.last_sync_date() == last_sync_date
  end

  describe "load_missed_transactions/2" do
    setup do
      start_supervised!({BeaconSummaryTimer, interval: "* * * * * *"})
      start_supervised!({BeaconSlotTimer, interval: "* * * * * *"})
      # Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))

      welcome_node = %Node{
        first_public_key: "key1",
        last_public_key: "key1",
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        reward_address: :crypto.strong_rand_bytes(32),
        enrollment_date: DateTime.utc_now(),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10)
      }

      coordinator_node = %Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        available?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10),
        geo_patch: "AAA",
        network_patch: "AAA",
        reward_address: :crypto.strong_rand_bytes(32),
        enrollment_date: DateTime.utc_now()
      }

      storage_nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key3",
          last_public_key: "key3",
          available?: true,
          geo_patch: "BBB",
          network_patch: "BBB",
          reward_address: :crypto.strong_rand_bytes(32),
          enrollment_date: DateTime.utc_now(),
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-10)
        }
      ]

      Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

      P2P.add_and_connect_node(welcome_node)
      P2P.add_and_connect_node(coordinator_node)

      {:ok,
       %{
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         storage_nodes: storage_nodes
       }}
    end

    test "should retrieve the missing beacon summaries from the given date", context do
      Crypto.generate_deterministic_keypair("daily_nonce_seed")
      |> elem(0)
      |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now())

      inputs = [
        %TransactionInput{
          from: "@Alice2",
          amount: 1_000_000_000,
          spent?: true,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      tx = TransactionFactory.create_valid_transaction(context, inputs)

      me = self()

      MockDB
      |> stub(:write_transaction_chain, fn _ ->
        send(me, :storage)
        :ok
      end)
      |> stub(:write_transaction, fn _, _ -> :ok end)

      summary = %BeaconSummary{
        subset: <<0>>,
        summary_time: DateTime.utc_now(),
        transaction_summaries: [
          %TransactionSummary{
            address: tx.address,
            type: :transfer,
            timestamp: DateTime.utc_now()
          }
        ]
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetBeaconSummary{address: _address} ->
          {:ok, summary}

        _, %GetTransaction{address: address} ->
          if address == tx.address do
            {:ok, tx}
          else
            tx_content =
              summary
              |> BeaconSummary.serialize()
              |> Utils.wrap_binary()

            {:ok,
             %Transaction{
               address: address,
               type: :beacon_summary,
               data: %TransactionData{content: tx_content}
             }}
          end

        _, %GetTransactionInputs{} ->
          {:ok, %TransactionInputList{inputs: inputs}}

        _, %GetTransactionChain{} ->
          {:ok, %TransactionList{transactions: []}}
      end)

      MockDB
      |> stub(:register_tps, fn _, _, _ -> :ok end)

      assert :ok = Sync.load_missed_transactions(DateTime.utc_now() |> DateTime.add(-1), "AAA")

      assert_receive :storage
    end
  end
end
