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
    SelfRepairScheduler.start_link(interval: "0 0 * * *")
    :ok
  end

  describe "start_link/1" do
    test "should start the process with idle state and initialize the polling date" do
      {:ok, pid} =
        Scheduler.start_link(polling_interval: "0 * * * *", summary_interval: "0 0 0 * *")

      polling_date =
        "0 * * * *"
        |> Crontab.CronExpression.Parser.parse!(true)
        |> Crontab.Scheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
        |> DateTime.from_naive!("Etc/UTC")

      summary_date =
        "0 0 0 * *"
        |> Crontab.CronExpression.Parser.parse!(true)
        |> Crontab.Scheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
        |> DateTime.from_naive!("Etc/UTC")

      assert {:idle, %{polling_date: ^polling_date, summary_date: ^summary_date}} =
               :sys.get_state(pid)
    end
  end

  describe "when receives a poll message" do
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
        Scheduler.start_link(polling_interval: "0 * * * *", summary_interval: "0 0 0 * *")

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
        Scheduler.start_link(polling_interval: "0 * * * *", summary_interval: "0 0 0 * *")

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

      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => 0.2}} end)

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

      assert tx_address ==
               Crypto.derive_oracle_keypair(summary_date, 1)
               |> elem(0)
               |> Crypto.derive_address()

      assert {:ok, %{"uco" => %{"usd" => 0.2}}} = Services.parse_data(Jason.decode!(content))

      assert {:ready, %{polling_timer: polling_timer}} = :sys.get_state(pid)

      Process.cancel_timer(polling_timer)
    end

    test "should not send a new transaction when the fetched data is the same" do
      {:ok, pid} =
        Scheduler.start_link(polling_interval: "0 * * * *", summary_interval: "0 0 0 * *")

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
      |> expect(:get_transaction, fn _, _ ->
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

      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => 0.2}} end)

      send(pid, :poll)

      refute_receive {:transaction_sent, _}
    end

    test "if the date is the summary date, it should generate summary transaction, followed by an polling oracle transaction" do
      {:ok, pid} =
        Scheduler.start_link(polling_interval: "0 0 0 * *", summary_interval: "0 0 0 * *")

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

      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => 0.2}} end)

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
  end

  property "dates and address stay in sync over pollings" do
    {:ok, pid} =
      Scheduler.start_link(polling_interval: "0 * * * *", summary_interval: "0 0 0 * *")

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

    # polling_date =
    #   "0 * * * *"
    #   |> Crontab.CronExpression.Parser.parse!(true)
    #   |> Crontab.Scheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
    #   |> DateTime.from_naive!("Etc/UTC")

    # summary_date =
    #   "0 0 0 * *"
    #   |> Crontab.CronExpression.Parser.parse!(true)
    #   |> Crontab.Scheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
    #   |> DateTime.from_naive!("Etc/UTC")

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
    end)

    check all(price <- StreamData.float(min: 0.001)) do
      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => price}} end)

      #  MockDB
      #  |> stub(:chain_size, fn _ -> index - 1 end)

      send(pid, :poll)

      assert_receive {:transaction_sent,
                      %Transaction{address: tx_address, data: %TransactionData{content: content}}}

      assert {:ready,
              %{polling_timer: polling_timer, summary_date: summary_date, indexes: indexes}} =
               :sys.get_state(pid)

      index = Map.get(indexes, summary_date)

      assert tx_address ==
               Crypto.derive_oracle_keypair(summary_date, index + 1)
               |> elem(0)
               |> Crypto.derive_address()

      assert {:ok, %{"uco" => %{"usd" => ^price}}} = Services.parse_data(Jason.decode!(content))

      Process.cancel_timer(polling_timer)
    end
  end

  property "dates and address are in sync over the summaries" do
    {:ok, pid} =
      Scheduler.start_link(polling_interval: "0 * * * *", summary_interval: "0 0 * * *")

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

    # polling_date =
    #  "0 * * * *"
    #  |> Crontab.CronExpression.Parser.parse!(true)
    #  |> Crontab.Scheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
    #  |> DateTime.from_naive!("Etc/UTC")

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

    check all(
            price <- StreamData.float(min: 0.001)
            # index <- StreamData.sized(fn size -> StreamData.constant(size) end)
          ) do
      MockUCOPriceProvider
      |> expect(:fetch, fn _pairs -> {:ok, %{"usd" => price}} end)

      send(pid, :poll)

      assert_receive {:transaction_sent,
                      %Transaction{address: tx_address, data: %TransactionData{content: content}}}

      assert {:ready,
              %{
                summary_date: summary_date,
                polling_timer: polling_timer,
                indexes: indexes
              }} = :sys.get_state(pid)

      index = Map.get(indexes, summary_date)

      assert tx_address ==
               Crypto.derive_oracle_keypair(summary_date, index + 1)
               |> elem(0)
               |> Crypto.derive_address()

      assert {:ok, %{"uco" => %{"usd" => ^price}}} = Services.parse_data(Jason.decode!(content))

      Process.cancel_timer(polling_timer)
    end
  end
end
