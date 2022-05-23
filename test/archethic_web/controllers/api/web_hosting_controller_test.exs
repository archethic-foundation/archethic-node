defmodule ArchethicWeb.API.WebHostingControllerTest do
  use ArchethicCase
  use ArchethicWeb.ConnCase

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Crypto

  alias Archethic.P2P.Message.GetLastTransaction

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    :ok
  end

  describe "web_hosting/2" do
    test "should return Invalid address", %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, %GetLastTransaction{}, _ ->
        {:error, :transaction_not_exists}
      end)

      conn1 = get(conn, "/api/web_hosting/AZERTY")
      conn2 = get(conn, "/api/web_hosting/0123456789")

      conn3 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba"
        )

      assert "Invalid address" = response(conn1, 400)
      assert "Invalid address" = response(conn2, 400)
      assert "Invalid address" = response(conn3, 400)
    end

    test "should return Invalid transaction content", %{conn: conn} do
      MockClient
      |> stub(:send_message, fn _, %GetLastTransaction{}, _ ->
        {:ok,
         %Transaction{
           address: "0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba",
           data: %TransactionData{content: "invalid"}
         }}
      end)

      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba"
        )

      assert "Invalid transaction content" = response(conn, 400)
    end
  end

  describe "get_file/2" do
    setup do
      content = """
      {
        "index.html":{
          "encodage":"base64",
          "content":"PGgxPkFyY2hldGhpYzwvaDE-"
        },
        "folder":{
          "hello_world.html":{
            "encodage":"base64",
            "content":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg"
          }
        }
      }
      """

      MockClient
      |> stub(:send_message, fn _, %GetLastTransaction{}, _ ->
        {:ok,
         %Transaction{
           address: "0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba",
           data: %TransactionData{content: content}
         }}
      end)

      :ok
    end

    test "should return file does not exist", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/file.html"
        )

      assert "File file.html does not exist" = response(conn, 404)
    end

    test "should return default index.html file", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba"
        )

      assert "<h1>Archethic</h1>" = response(conn, 200) |> :zlib.gunzip()
    end

    test "should return selected file", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/folder/hello_world.html"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200) |> :zlib.gunzip()
    end
  end

  describe "get_file_content/2" do
    setup do
      content = """
      {
        "error.html":{
          "encodage":"base64",
          "content":"4rdHFh%2BHYoS8oLdVvbUzEVqB8Lvm7kSPnuwF0AAABYQ%3D"
        },
        "base64.js":{
          "encodage":"base64",
          "content":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg"
        },
        "unsupported.xml":{
          "encodage":"unsupported",
          "content":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg"
        },
        "raw.html":{
          "content":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg"
        },
        "no_content.html":{
          "unsupported":"unsupported"
        },
        "image.png":{
          "content":"image"
        }
      }
      """

      MockClient
      |> stub(:send_message, fn _, %GetLastTransaction{}, _ ->
        {:ok,
         %Transaction{
           address: "0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba",
           data: %TransactionData{content: content}
         }}
      end)

      :ok
    end

    test "should return Invalid file encodage", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/error.html"
        )

      assert "Invalid file encodage" = response(conn, 400)
    end

    test "should return Cannot find file content", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/no_content.html"
        )

      assert "Cannot find file content" = response(conn, 400)
    end

    test "should return decoded file content", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/base64.js"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200) |> :zlib.gunzip()
    end

    test "should return raw file content", %{conn: conn} do
      conn1 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/raw.html"
        )

      conn2 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/unsupported.xml"
        )

      assert "PGgxPkhlbGxvIHdvcmxkICE8L2gxPg" = response(conn1, 200) |> :zlib.gunzip()
      assert "PGgxPkhlbGxvIHdvcmxkICE8L2gxPg" = response(conn2, 200) |> :zlib.gunzip()
    end

    test "should return good file content-type", %{conn: conn} do
      conn1 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/raw.html"
        )

      conn2 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/unsupported.xml"
        )

      conn3 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/base64.js"
        )

      conn4 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/image.png"
        )

      assert ["text/html; charset=utf-8"] = get_resp_header(conn1, "content-type")
      assert ["text/xml; charset=utf-8"] = get_resp_header(conn2, "content-type")
      assert ["text/javascript; charset=utf-8"] = get_resp_header(conn3, "content-type")
      assert ["image/png; charset=utf-8"] = get_resp_header(conn4, "content-type")
    end
  end
end
