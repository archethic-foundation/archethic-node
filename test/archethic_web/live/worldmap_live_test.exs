defmodule ArchEthicWeb.WorldMapLiveTest do
  @moduledoc """
  This module defines the test case to be used by
  WorlMapLive tests.
  """
  use ArchEthicCase
  use ArchEthicWeb.ConnCase

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias ArchEthic.{
    Crypto,
    P2P,
    P2P.Node
  }

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3002,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      network_patch: "F1B",
      geo_patch: "F1B",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    :ok
  end

  describe "mount/3" do
    test "should render", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/explorer/nodes/worldmap")
      assert html =~ "worldmap"
    end

    test "should push worldmap_init_datas event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/explorer/nodes/worldmap")

      data = %{
        worldmap_datas: [
          %{
            coords: %{
              lat: [33.75, 39.375],
              lon: [-5.625, 0.0]
            },
            geo_patch: "F1B",
            nb_of_nodes: 1
          }
        ]
      }

      assert_push_event(view, "worldmap_init_datas", ^data)
    end
  end

  describe "handle_info/2" do
    test "shoud handle event and send wordlmap_update_datas event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/explorer/nodes/worldmap")

      send(view.pid, {:node_update, %Node{}})

      data = %{
        worldmap_datas: [
          %{
            coords: %{
              lat: [33.75, 39.375],
              lon: [-5.625, 0.0]
            },
            geo_patch: "F1B",
            nb_of_nodes: 1
          }
        ]
      }

      assert_push_event(view, "worldmap_update_datas", ^data)
    end
  end
end
