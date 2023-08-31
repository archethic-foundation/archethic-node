defmodule ArchethicWeb.API.JsonRPCControllerTest do
  use ArchethicCase
  use ArchethicWeb.ConnCase

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.Ok

  alias Archethic.SelfRepair.NetworkView

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    start_supervised!(NetworkView)

    MockClient
    |> stub(:send_message, fn _, _, _ -> {:ok, %Ok{}} end)

    :ok
  end

  describe "rpc" do
    test "should respect JSON RPC specification in case of success", %{conn: conn} do
      assert %{"jsonrpc" => "2.0", "id" => 1, "result" => _} =
               valid_rpc_request() |> send_request(conn)
    end

    test "should respect JSON RPC specification in cas of error", %{
      conn: conn
    } do
      assert %{"jsonrpc" => "2.0", "error" => %{"code" => _, "message" => _}, "id" => nil} =
               send_request(%{}, conn)
    end

    test "should return parse_error if request is not a JSON", %{
      conn: conn
    } do
      assert %{"error" => %{"code" => -32700}} = send_request(%{}, conn)
    end

    test "should return invalid_request if request does not respect JSON RPC specifications", %{
      conn: conn
    } do
      assert %{"error" => %{"code" => -32600}} = send_request(%{"json" => "1.0"}, conn)
    end

    test "should return method not exists if method does not exists", %{
      conn: conn
    } do
      assert %{"error" => %{"code" => -32601}} =
               valid_rpc_request(method: "abc") |> send_request(conn)
    end

    test "should return method not exists if method params are invalid", %{
      conn: conn
    } do
      assert %{"error" => %{"code" => -32602}} =
               valid_rpc_request(params: %{"invalid" => 3}) |> send_request(conn)
    end

    test "should handle batch of request", %{conn: conn} do
      requests = %{"_json" => [valid_rpc_request(id: 1), valid_rpc_request(id: 2)]}

      assert Enum.all?(send_request(requests, conn), &(&1["id"] in [1, 2]))
    end

    test "should return internal error when batch limit size is reached", %{conn: conn} do
      requests = Enum.map(1..21, &valid_rpc_request(id: &1))

      assert %{"error" => %{"code" => -32603}} = send_request(%{"_json" => requests}, conn)
    end
  end

  defp send_request(request, conn), do: post(conn, "/api/rpc", request) |> json_response(200)

  defp valid_rpc_request(opts \\ []) do
    id = Keyword.get(opts, :id, 1)
    method = Keyword.get(opts, :method, "send_transaction")
    params = Keyword.get(opts, :params, %{"transaction" => valid_tx_param()})

    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }
  end

  defp valid_tx_param(opts \\ []) do
    type = Keyword.get(opts, :type, "data")

    %{
      "version" => 1,
      "address" => "0000a9f3bc500d0ed7d923e983eafc080113633456f53c400814e1d4f34c5fa67220",
      "type" => type,
      "data" => %{
        "content" => "hello",
        "code" => "",
        "ownerships" => [],
        "ledger" => %{
          "uco" => %{
            "transfers" => []
          },
          "token" => %{
            "transfers" => []
          }
        },
        "recipients" => []
      },
      "previousPublicKey" =>
        "0001dcdd0f11174a0b832e77c1176aeca5220e7e7999d985890273497845b84f823b",
      "previousSignature" =>
        "8d213927cfedcdbe2b8ef537342e311820f87b3207b44127c4114061ed2b13a0a13d32fa758b0f984e295d9f0c8e955be0a06ee8755b7cf12f500b9596a9050a",
      "originSignature" =>
        "3045022036dc31960cf6a11ca764055542b49d57afec4eb93af3b0907c30aa283202e503022100861260f8778f63693c42b03af7cec24b03330935c1ead2f1e17133186d08d740"
    }
  end
end
