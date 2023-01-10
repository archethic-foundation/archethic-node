defmodule Archethic.OracleChain.SchedulerTest do
  use ArchethicCase
  use ExUnitProperties

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Node

  alias Archethic.OracleChain.Scheduler
  alias Archethic.OracleChain.Services

  alias Archethic.SelfRepair.Scheduler, as: SelfRepairScheduler

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  import Mox

  setup do
    SelfRepairScheduler.start_link([interval: "0 0 * * *"], [])
    :ok
  end

  describe "Oracle Scheduler: when receives a poll message" do
    setup do
      me = self()

      MockClient
      |> stub(:send_message, fn
        _,
        %StartMining{
          transaction:
            tx = %Transaction{
              type: :oracle
            }
        },
        _ ->
          send(me, {:transaction_sent, tx})
          {:ok, %Ok{}}

        _,
        %StartMining{
          transaction:
            tx = %Transaction{
              type: :oracle_summary
            }
        },
        _ ->
          send(me, {:transaction_summary_sent, tx})
          {:ok, %Ok{}}
      end)

      :ok
    end

    test "if not trigger node, it should skip the polling" do
      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"], [])

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      send(pid, :poll)
      refute_received {:transaction_sent, _}
    end

    test "if trigger node, it should fetch new data and create a new transaction" do
      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"], [])

      assert {:idle, %{polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle,
              %{indexes: %{}, polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      assert {:scheduled, _} = :sys.get_state(pid)

      MockUCOPriceProvider1
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      MockUCOPriceProvider2
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      MockUCOPriceProvider3
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      # polling_date =
      #   "0 * * * *"
      #   |> Crontab.CronExpression.Parser.parse!(true)
      #   |> Crontab.Scheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
      #   |> DateTime.from_naive!("Etc/UTC")

      summary_date =
        "0 0 0 * *"
        |> Crontab.CronExpression.Parser.parse!(true)
        |> Crontab.Scheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
        |> DateTime.from_naive!("Etc/UTC")

      send(pid, :poll)

      assert_receive {:transaction_sent,
                      %Transaction{address: tx_address, data: %TransactionData{content: content}}}

      assert {:triggered, %{polling_timer: polling_timer}} = :sys.get_state(pid)

      assert tx_address ==
               Crypto.derive_oracle_keypair(summary_date, 1)
               |> elem(0)
               |> Crypto.derive_address()

      assert {:ok, %{"uco" => %{"usd" => 0.2}}} = Services.parse_data(Jason.decode!(content))

      Process.cancel_timer(polling_timer)
    end

    test "should not send a new transaction when the fetched data is the same" do
      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"], [])

      assert {:idle, %{polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle,
              %{indexes: %{}, polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      MockDB
      |> expect(:get_transaction, fn _, _, _ ->
        {:ok,
         %Transaction{
           type: :oracle,
           data: %TransactionData{
             content:
               Jason.encode!(%{
                 "uco" => %{
                   "usd" => 0.2
                 }
               })
           }
         }}
      end)

      MockUCOPriceProvider1
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      MockUCOPriceProvider2
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      MockUCOPriceProvider3
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      send(pid, :poll)

      refute_receive {:transaction_sent, _}
    end

    test "if the date is the summary date, it should generate summary transaction, followed by an polling oracle transaction" do
      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 0 0 * *", summary_interval: "0 0 0 * *"], [])

      assert {:idle, %{polling_interval: "0 0 0 * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle,
              %{indexes: %{}, polling_interval: "0 0 0 * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      MockUCOPriceProvider1
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      MockUCOPriceProvider2
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      MockUCOPriceProvider3
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      summary_date =
        "0 0 0 * *"
        |> Crontab.CronExpression.Parser.parse!(true)
        |> Crontab.Scheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
        |> DateTime.from_naive!("Etc/UTC")

      #  summary_date2 =
      #    "0 0 0 * *"
      #    |> Crontab.CronExpression.Parser.parse!(true)
      #    |> Crontab.Scheduler.get_next_run_dates(DateTime.to_naive(DateTime.utc_now()))
      #    |> Enum.at(1)
      #    |> DateTime.from_naive!("Etc/UTC")

      MockDB
      |> expect(:get_transaction_chain, fn _, _, _ ->
        {[
           %Transaction{
             address:
               Crypto.derive_oracle_keypair(summary_date, 1) |> elem(0) |> Crypto.derive_address(),
             type: :oracle,
             data: %TransactionData{
               content:
                 Jason.encode!(%{
                   "uco" => %{
                     "usd" => 0.2
                   }
                 })
             },
             validation_stamp: %ValidationStamp{timestamp: ~U[2021-12-10 10:05:00Z]}
           }
         ], false, nil}
      end)

      send(pid, :poll)

      assert_receive {:transaction_summary_sent,
                      %Transaction{
                        address: summary_address,
                        type: :oracle_summary,
                        data: %TransactionData{content: content}
                      }}

      timestamp = DateTime.to_unix(~U[2021-12-10 10:05:00Z]) |> Integer.to_string()

      assert summary_address ==
               Crypto.derive_oracle_keypair(summary_date, 1)
               |> elem(0)
               |> Crypto.derive_address()

      assert %{
               ^timestamp => %{
                 "uco" => %{
                   "usd" => 0.2
                 }
               }
             } = Jason.decode!(content)

      send(pid, {:new_transaction, summary_address, :oracle_summary, DateTime.utc_now()})

      assert_receive {:transaction_sent,
                      %Transaction{
                        address: _polling_address,
                        type: :oracle,
                        data: %TransactionData{content: content}
                      }}

      #      assert polling_address ==
      #               Crypto.derive_oracle_keypair(summary_date2, 1)
      #               |> elem(0)
      #               |> Crypto.hash()
      #
      assert {:ok, %{"uco" => %{"usd" => 0.2}}} = Services.parse_data(Jason.decode!(content))
    end

    test "should reschedule after tx replication" do
      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 * * * * *", summary_interval: "0 0 0 * *"], [])

      assert {:idle, %{polling_interval: "0 * * * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle,
              %{indexes: %{}, polling_interval: "0 * * * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      assert {:scheduled, %{polling_timer: timer1}} = :sys.get_state(pid)

      MockUCOPriceProvider1
      |> stub(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      MockUCOPriceProvider2
      |> stub(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      MockUCOPriceProvider3
      |> stub(:fetch, fn _pairs -> {:ok, %{"usd" => [0.2]}} end)

      send(pid, :poll)

      assert_receive {:transaction_sent, %Transaction{address: tx_address}}

      send(pid, {:new_transaction, tx_address, :oracle, DateTime.utc_now()})
      assert {:scheduled, %{polling_timer: timer2}} = :sys.get_state(pid)

      assert timer2 != timer1
    end
  end

  describe "Scheduler Behavior During start" do
    test "should be idle when node has not done Bootstrapping" do
      :persistent_term.put(:archethic_up, nil)

      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"], [])

      assert {:idle, %{polling_interval: "0 * * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)
    end

    test "should wait for node up message to start the scheduler, node: not authorized and available" do
      :persistent_term.put(:archethic_up, nil)

      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 */2 * * *", summary_interval: "0 0 0 * *"], [])

      assert {:idle, %{polling_interval: "0 */2 * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle,
              %{
                indexes: %{},
                polling_interval: "0 */2 * * *",
                summary_interval: "0 0 0 * *"
              }} = :sys.get_state(pid)
    end

    test "should wait for node up message to start the scheduler, node: authorized and available" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 */3 * * *", summary_interval: "0 0 0 * *"], [])

      assert {:idle, %{polling_interval: "0 */3 * * *", summary_interval: "0 0 0 * *"}} =
               :sys.get_state(pid)

      send(pid, :node_up)

      assert {:scheduled,
              %{
                indexes: _,
                polling_interval: "0 */3 * * *",
                summary_interval: "0 0 0 * *",
                summary_date: _date_time = %DateTime{}
              }} = :sys.get_state(pid)
    end

    test "Should use persistent_term :archethic_up when a Scheduler crashes,current node: Not authorized and available" do
      :persistent_term.put(:archethic_up, :up)

      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 */4 * * *", summary_interval: "0 0 0 * *"], [])

      assert {:idle,
              %{
                polling_interval: "0 */4 * * *",
                summary_interval: "0 0 0 * *",
                indexes: %{}
              }} = :sys.get_state(pid)

      :persistent_term.put(:archethic_up, nil)
    end

    test "Should use persistent_term :archethic_up when a Scheduler crashes,current node: authorized and available" do
      :persistent_term.put(:archethic_up, :up)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      {:ok, pid} =
        Scheduler.start_link([polling_interval: "0 */6 * * *", summary_interval: "0 0 0 * *"], [])

      assert {:scheduled,
              %{
                polling_interval: "0 */6 * * *",
                summary_interval: "0 0 0 * *",
                summary_date: _date_time = %DateTime{},
                indexes: _
              }} = :sys.get_state(pid)

      :persistent_term.put(:archethic_up, nil)
    end
  end
end
