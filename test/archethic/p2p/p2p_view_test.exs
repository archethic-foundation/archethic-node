defmodule Archethic.P2P.P2PViewTest do
  use ArchethicCase

  alias Archethic.P2P.P2PView

  # import ArchethicCase

  # Doit stocker sur disque les années précédentes

  setup do
    {:ok, _pid} = P2PView.start_link()
    :ok
  end

  @spec init_p2pview(id :: non_neg_integer()) :: P2PView.t()
  defp init_p2pview(id) do
    %P2PView{
      geo_patch: "AAA",
      available?: true,
      avg_availability: id / 10
    }
  end

  @doc """
  Gets P2PView nodes from unix timestamp.
  """
  def get_summary(timestamp) do
    P2PView.get_summary(DateTime.from_unix!(timestamp))
  end

  describe "get_summary/1" do
    test "should return the requested timestamp data when available" do
      node1 = init_p2pview(1)
      node2 = init_p2pview(2)

      date0 = DateTime.truncate(DateTime.utc_now(), :second)
      date3 = DateTime.add(date0, 3)

      # Given
      #  0 : [node1]
      #  3 : [node1, node2]
      P2PView.add_node(node1, date0, fn _ -> 0 end)
      P2PView.add_node(node2, date3, fn _ -> 1 end)

      assert [node1, node2] == P2PView.get_summary(date3)
    end

    test "should return the previous timestamp state when no data at requested timestamp" do
      node1 = init_p2pview(1)
      node2 = init_p2pview(2)

      date0 = DateTime.truncate(DateTime.utc_now(), :second)
      date2 = DateTime.add(date0, 2)
      date3 = DateTime.add(date0, 3)

      # Given
      #  0 : [node1]
      #  2 : [node1, node2]
      P2PView.add_node(node1, date0, fn _ -> 0 end)
      P2PView.add_node(node2, date2, fn _ -> 1 end)

      assert [node1, node2] == P2PView.get_summary(date3)
    end
  end

  describe "add_node/3" do
    test "should update first record and the following ones" do
      node1 = init_p2pview(1)
      node2 = init_p2pview(2)
      node3 = init_p2pview(3)

      date0 = DateTime.truncate(DateTime.utc_now(), :second)
      date3 = DateTime.add(date0, 3)

      # Given
      #  0 : [node1]
      #  3 : [node1, node2]
      P2PView.add_node(node1, date0, fn _ -> 0 end)
      P2PView.add_node(node2, date3, fn _ -> 1 end)

      # When adding a new node from timestamp 1
      assert :ok ==
               P2PView.add_node(
                 node3,
                 date0,
                 fn
                   ^date0 -> 1
                   _ -> 2
                 end
               )

      assert [node1, node3] == P2PView.get_summary(date0)
      assert [node1, node2, node3] == P2PView.get_summary(date3)
    end

    test "should create first record and update the following ones" do
      node1 = init_p2pview(1)
      node2 = init_p2pview(2)
      node3 = init_p2pview(3)

      date0 = DateTime.truncate(DateTime.utc_now(), :second)
      date1 = DateTime.add(date0, 1)
      date3 = DateTime.add(date0, 3)

      # Given
      #  0 : [node1]
      #  3 : [node1, node2]
      P2PView.add_node(node1, date0, fn _ -> 0 end)
      P2PView.add_node(node2, date3, fn _ -> 1 end)

      # When adding a new node from timestamp 1
      assert :ok ==
               P2PView.add_node(
                 node3,
                 date1,
                 fn
                   ^date1 -> 0
                   _ -> 1
                 end
               )

      assert [node1] == P2PView.get_summary(date0)
      assert [node3, node1] == P2PView.get_summary(date1)
      assert [node1, node3, node2] == P2PView.get_summary(date3)
    end
  end

  describe "update_node/2" do
    test "should update first record and the following ones" do
      node1 = init_p2pview(1)
      node2 = init_p2pview(2)
      node3 = init_p2pview(3)

      date0 = DateTime.truncate(DateTime.utc_now(), :second)
      date1 = DateTime.add(date0, 1)
      date3 = DateTime.add(date0, 3)

      # Given
      #  0 : [node1]
      #  1 : [node1, node2]
      #  3 : [node1, node2, node3]
      P2PView.add_node(node1, date0, fn _ -> 0 end)
      P2PView.add_node(node2, date1, fn _ -> 1 end)
      P2PView.add_node(node3, date3, fn _ -> 2 end)

      # When updating node 2 from timestamp 3
      assert :ok ==
               P2PView.update_node(
                 [avg_availability: 0.5],
                 date1,
                 fn _ -> 1 end
               )

      updated_node_2 = %{node2 | avg_availability: 0.5}

      assert [node1] == P2PView.get_summary(date0)
      assert [node1, updated_node_2] == P2PView.get_summary(date1)
      assert [node1, updated_node_2, node3] == P2PView.get_summary(date3)
    end
  end

  test "should create first record and update the following ones" do
    node1 = init_p2pview(1)
    node2 = init_p2pview(2)

    date0 = DateTime.truncate(DateTime.utc_now(), :second)
    date1 = DateTime.add(date0, 1)
    date2 = DateTime.add(date0, 2)
    date3 = DateTime.add(date0, 3)

    # Given
    #  0 : [node1]
    #  1 : [node1, node2]
    #  3 : [node1, node2]
    P2PView.add_node(node1, date0, fn _ -> 0 end)
    P2PView.add_node(node2, date1, fn _ -> 1 end)

    # When updating node 2 from timestamp 2
    assert :ok ==
             P2PView.update_node(
               [avg_availability: 0.5],
               date2,
               fn _ -> 1 end
             )

    updated_node_2 = %{node2 | avg_availability: 0.5}

    assert [node1] == P2PView.get_summary(date0)
    assert [node1, node2] == P2PView.get_summary(date1)
    assert [node1, updated_node_2] == P2PView.get_summary(date2)
    assert [node1, updated_node_2] == P2PView.get_summary(date3)
  end

  test "should update nodes properties until another mutation is met" do
    node1 = init_p2pview(1)

    date0 = DateTime.truncate(DateTime.utc_now(), :second)
    date1 = DateTime.add(date0, 1)
    date2 = DateTime.add(date0, 2)

    # Given
    #  0 : [node1]
    P2PView.add_node(node1, date0, fn _ -> 0 end)

    # Given a mutation on timestamp 1
    P2PView.update_node(
      [geo_patch: "CCC"],
      date1,
      fn _ -> 0 end
    )

    P2PView.update_node(
      [avg_availability: 0.5],
      date2,
      fn _ -> 0 end
    )

    # When updating node 1 from timestamp 0
    assert :ok ==
             P2PView.update_node(
               [geo_patch: "BBB", avg_availability: 0.3],
               date0,
               fn _ -> 0 end
             )

    assert [%{node1 | avg_availability: 0.3, geo_patch: "BBB"}] == P2PView.get_summary(date0)
    assert [%{node1 | avg_availability: 0.3, geo_patch: "CCC"}] == P2PView.get_summary(date1)
    assert [%{node1 | avg_availability: 0.5, geo_patch: "CCC"}] == P2PView.get_summary(date2)
  end
end
