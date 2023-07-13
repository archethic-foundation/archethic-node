defmodule ArchethicWeb.WorldMapLiveTest do
  @moduledoc """
  This module defines the test case to be used by
  WorlMapLive tests.
  """
  use ArchethicCase
  use ArchethicWeb.ConnCase

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Mox

  alias Archethic.{
    P2P,
    P2P.Node
  }

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3002,
      first_public_key: "key1",
      last_public_key: "key1",
      network_patch: "F1B",
      geo_patch: "F1B",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      ip: {88, 22, 30, 229},
      port: 3002,
      first_public_key: "key2",
      last_public_key: "key2",
      network_patch: "F1B",
      geo_patch: "F1B",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      ip: {88, 22, 30, 229},
      port: 3002,
      first_public_key: "key3",
      last_public_key: "key3",
      network_patch: "F1B",
      geo_patch: "F1B",
      available?: true,
      authorized?: false,
      authorization_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      ip: {88, 22, 30, 229},
      port: 3002,
      first_public_key: "key4",
      last_public_key: "key4",
      network_patch: "F1B",
      geo_patch: "F1B",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    stub(MockGeoIP, :get_coordinates, fn ip ->
      case ip do
        # Spain (Alicante)
        {88, 22, 30, 229} ->
          {38.345170, -0.481490}

        # Local Node
        {127, 0, 0, 1} ->
          {0.0, 0.0}
      end
    end)

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
              lat: [45.0, 50.625],
              lon: [5.625, 11.25]
            },
            geo_patch: "021",
            nb_of_nodes: 1,
            authorized: true
          },
          %{
            coords: %{
              lat: [33.75, 39.375],
              lon: [-5.625, 0.0]
            },
            geo_patch: "F1B",
            nb_of_nodes: 1,
            authorized: false
          },
          %{
            coords: %{
              lat: [33.75, 39.375],
              lon: [-5.625, 0.0]
            },
            geo_patch: "F1B",
            nb_of_nodes: 2,
            authorized: true
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
              lat: [45.0, 50.625],
              lon: [5.625, 11.25]
            },
            geo_patch: "021",
            nb_of_nodes: 1,
            authorized: true
          },
          %{
            coords: %{
              lat: [33.75, 39.375],
              lon: [-5.625, 0.0]
            },
            geo_patch: "F1B",
            nb_of_nodes: 1,
            authorized: false
          },
          %{
            coords: %{
              lat: [33.75, 39.375],
              lon: [-5.625, 0.0]
            },
            geo_patch: "F1B",
            nb_of_nodes: 2,
            authorized: true
          }
        ]
      }

      assert_push_event(view, "worldmap_update_datas", ^data)
    end
  end
end
