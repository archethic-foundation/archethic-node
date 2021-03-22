defmodule Uniris.P2P.BatcherTest do
  use UnirisCase

  alias Uniris.BeaconChain.Slot

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.GetBeaconSlot
  alias Uniris.P2P.Message.NotifyBeaconSlot
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node

  import Mox

  describe "add_broadcast_request/2" do
    test "should reference a broadcast request for a node to execute later" do
      {:ok, pid} = Batcher.start_link([timeout: 2_000], [])

      Task.async_stream(1..256, fn _ ->
        :ok =
          Batcher.add_broadcast_request(
            pid,
            [%Node{first_public_key: "key1"}],
            %NotifyBeaconSlot{
              slot: %Slot{}
            }
          )
      end)
      |> Stream.run()

      assert %{broadcast_queue: broadcast_queue, timer: timer} = :sys.get_state(pid)

      assert [%NotifyBeaconSlot{slot: %Slot{}} | rest] =
               Map.get(broadcast_queue, %Node{first_public_key: "key1"})

      assert length(rest) == 255
      Process.cancel_timer(timer)
    end

    test "should send 1 broadcast request for 256 messages targeting a single node" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 1, fn _, %BatchRequests{requests: requests}, _
                                     when length(requests) == 256 ->
        {:ok, %Ok{}}
      end)

      Task.async_stream(1..256, fn _ ->
        :ok =
          Batcher.add_broadcast_request(
            pid,
            [%Node{first_public_key: "key1"}],
            %NotifyBeaconSlot{
              slot: %Slot{}
            }
          )
      end)
      |> Stream.run()

      Process.sleep(200)

      assert %{broadcast_queue: %{}, timer: timer} = :sys.get_state(pid)
      Process.cancel_timer(timer)
    end

    test "should send 5 broadcast request for 256 messages targeting a 5 nodes" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 5, fn _, %BatchRequests{requests: requests}, _
                                     when length(requests) == 256 ->
        {:ok, %Ok{}}
      end)

      Enum.each(0..255, fn i ->
        :ok =
          Batcher.add_broadcast_request(
            pid,
            [
              %Node{first_public_key: "key1"},
              %Node{first_public_key: "key2"},
              %Node{first_public_key: "key3"},
              %Node{first_public_key: "key4"},
              %Node{first_public_key: "key5"}
            ],
            %NotifyBeaconSlot{
              slot: %Slot{subset: <<i>>}
            }
          )
      end)

      Process.sleep(200)

      assert %{broadcast_queue: %{}, timer: timer} = :sys.get_state(pid)
      Process.cancel_timer(timer)
    end
  end

  describe "request_first_reply/2" do
    test "with a single request" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 1, fn _, %BatchRequests{requests: [%GetBeaconSlot{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %Slot{}}]}}
      end)

      P2P.add_node(%Node{first_public_key: Crypto.node_public_key(0), network_patch: "AAA"})

      assert {:ok, %Slot{}} =
               Batcher.request_first_reply(
                 pid,
                 [%Node{first_public_key: "key1", network_patch: "AAA"}],
                 %GetBeaconSlot{subset: <<0>>, slot_time: DateTime.utc_now()}
               )

      assert %{first_reply_queue: %{}, timer: timer} = :sys.get_state(pid)
      Process.cancel_timer(timer)
    end

    test "should send 1 request for 256 messages targeting a single node" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 1, fn _, %BatchRequests{requests: requests}, _ ->
        responses =
          requests
          |> Enum.with_index()
          |> Enum.map(fn {%GetBeaconSlot{}, index} ->
            {index, %Slot{}}
          end)

        {:ok, %BatchResponses{responses: responses}}
      end)

      P2P.add_node(%Node{first_public_key: Crypto.node_public_key(0), network_patch: "AAA"})

      assert 256 ==
               Task.async_stream(
                 0..255,
                 fn i ->
                   Batcher.request_first_reply(
                     pid,
                     [%Node{first_public_key: "key1", network_patch: "AAA"}],
                     %GetBeaconSlot{subset: <<i>>, slot_time: DateTime.utc_now()}
                   )
                 end,
                 max_concurrency: 256
               )
               |> Enum.count()

      assert %{first_reply_queue: %{}, timer: timer} = :sys.get_state(pid)
      Process.cancel_timer(timer)
    end

    test "should send 1 request to the closest node for 256 messages while targeting 5 nodes" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 1, fn _, %BatchRequests{requests: requests}, _ ->
        responses =
          requests
          |> Enum.with_index()
          |> Enum.map(fn {%GetBeaconSlot{}, index} ->
            {index, %Slot{}}
          end)

        {:ok, %BatchResponses{responses: responses}}
      end)

      P2P.add_node(%Node{first_public_key: Crypto.node_public_key(0), network_patch: "EDF"})

      assert 256 ==
               Task.async_stream(
                 0..255,
                 fn i ->
                   Batcher.request_first_reply(
                     pid,
                     [
                       %Node{first_public_key: "key1", network_patch: "AAA"},
                       %Node{first_public_key: "key2", network_patch: "BCE"},
                       %Node{first_public_key: "key3", network_patch: "A2C"},
                       %Node{first_public_key: "key4", network_patch: "FAC"},
                       %Node{first_public_key: "key5", network_patch: "DEF"}
                     ],
                     %GetBeaconSlot{subset: <<i>>, slot_time: DateTime.utc_now()}
                   )
                 end,
                 max_concurrency: 256
               )
               |> Enum.count()

      assert %{first_reply_queue: %{}, timer: timer} = :sys.get_state(pid)
      Process.cancel_timer(timer)
    end

    test "should send 2 requests to the closest nodes for 256 messages while targeting 5 nodes when the first node is failing" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 2, fn %Node{first_public_key: key},
                                     %BatchRequests{requests: requests},
                                     _ ->
        case key do
          "key4" ->
            {:error, :network_issue}

          _ ->
            responses =
              requests
              |> Enum.with_index()
              |> Enum.map(fn {%GetBeaconSlot{}, index} ->
                {index, %Slot{}}
              end)

            {:ok, %BatchResponses{responses: responses}}
        end
      end)

      P2P.add_node(%Node{first_public_key: Crypto.node_public_key(0), network_patch: "EDF"})

      assert 256 ==
               Task.async_stream(
                 0..255,
                 fn i ->
                   Batcher.request_first_reply(
                     pid,
                     [
                       %Node{first_public_key: "key1", network_patch: "AAA"},
                       %Node{first_public_key: "key2", network_patch: "BCE"},
                       %Node{first_public_key: "key3", network_patch: "A2C"},
                       %Node{first_public_key: "key4", network_patch: "FAC"},
                       %Node{first_public_key: "key5", network_patch: "DEF"}
                     ],
                     %GetBeaconSlot{subset: <<i>>, slot_time: DateTime.utc_now()}
                   )
                 end,
                 max_concurrency: 256
               )
               |> Enum.count()

      assert %{first_reply_queue: %{}, timer: timer} = :sys.get_state(pid)
      Process.cancel_timer(timer)
    end

    test "test" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 1, fn _, %BatchRequests{requests: requests}, _ ->
        responses =
          requests
          |> Enum.with_index()
          |> Enum.map(fn {%GetBeaconSlot{}, index} ->
            {index, %Slot{}}
          end)

        {:ok, %BatchResponses{responses: responses}}
      end)

      P2P.add_node(%Node{first_public_key: Crypto.node_public_key(0), network_patch: "EDF"})

      Enum.map(0..255, fn i ->
        {
          Enum.map(1..10, fn j ->
            %Node{first_public_key: "key#{j}", network_patch: "AAA"}
          end),
          i,
          DateTime.utc_now()
        }
      end)
      |> Task.async_stream(
        fn {nodes, subset, slot_time} ->
          Batcher.request_first_reply(pid, nodes, %GetBeaconSlot{
            subset: subset,
            slot_time: slot_time
          })
        end,
        max_concurrency: 256
      )
      |> Enum.to_list()
    end
  end

  describe "request_first_reply_with_ack/2" do
    test "should send a single request and return the node invovled" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 1, fn _, %BatchRequests{requests: [%GetBeaconSlot{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %Slot{}}]}}
      end)

      P2P.add_node(%Node{first_public_key: Crypto.node_public_key(0), network_patch: "AAA"})

      assert {:ok, %Slot{}, %Node{}} =
               Batcher.request_first_reply_with_ack(
                 pid,
                 [%Node{first_public_key: "key1", network_patch: "AAA"}],
                 %GetBeaconSlot{subset: <<0>>, slot_time: DateTime.utc_now()}
               )

      assert %{first_reply_queue: %{}, timer: timer} = :sys.get_state(pid)
      Process.cancel_timer(timer)
    end

    test "should send 1 request to the closest node for 256 messages while targeting 5 nodes and return the node invovled" do
      {:ok, pid} = Batcher.start_link([timeout: 100], [])

      MockClient
      |> expect(:send_message, 1, fn _, %BatchRequests{requests: requests}, _ ->
        responses =
          requests
          |> Enum.with_index()
          |> Enum.map(fn {%GetBeaconSlot{}, index} ->
            {index, %Slot{}}
          end)

        {:ok, %BatchResponses{responses: responses}}
      end)

      P2P.add_node(%Node{first_public_key: Crypto.node_public_key(0), network_patch: "EDF"})

      assert {:ok, %Slot{}, %Node{first_public_key: "key4"}} =
               Batcher.request_first_reply_with_ack(
                 pid,
                 [
                   %Node{first_public_key: "key1", network_patch: "AAA"},
                   %Node{first_public_key: "key2", network_patch: "BCE"},
                   %Node{first_public_key: "key3", network_patch: "A2C"},
                   %Node{first_public_key: "key4", network_patch: "FAC"},
                   %Node{first_public_key: "key5", network_patch: "DEF"}
                 ],
                 %GetBeaconSlot{subset: <<0>>, slot_time: DateTime.utc_now()}
               )

      assert %{first_reply_queue: %{}, timer: timer} = :sys.get_state(pid)
      Process.cancel_timer(timer)
    end
  end
end
