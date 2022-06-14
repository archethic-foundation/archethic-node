defmodule ArchethicWeb.API.WebHostingControllerTest do
  use ArchethicCase
  use ArchethicWeb.ConnCase

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Crypto

  alias Archethic.P2P.Message.GetLastTransaction
  alias Archethic.P2P.Message.GetTransaction

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

      conn1 = get(conn, "/api/web_hosting/AZERTY/")
      conn2 = get(conn, "/api/web_hosting/0123456789/")

      conn3 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/"
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
           address:
             <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126, 15,
               80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>,
           data: %TransactionData{content: "invalid"}
         }}
      end)

      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/"
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
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "folder":{
          "hello_world.html":{
            "encodage":"base64",
            "address":[
              "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
            ]
          }
        }
      }
      """

      content2 = """
      {
        "index.html":"PGgxPkFyY2hldGhpYzwvaDE-",
        "folder":{
          "hello_world.html":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg"
        }
      }
      """

      MockClient
      |> stub(:send_message, fn _, message, _ ->
        case message do
          %GetLastTransaction{} ->
            {:ok,
             %Transaction{
               address:
                 <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                   15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>,
               data: %TransactionData{content: content}
             }}

          %GetTransaction{} ->
            {:ok,
             %Transaction{
               data: %TransactionData{content: content2}
             }}
        end
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
      conn = put_req_header(conn, "accept-encoding", "[gzip]")

      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/"
        )

      assert "<h1>Archethic</h1>" = response(conn, 200) |> :zlib.gunzip()
    end

    test "should return selected file", %{conn: conn} do
      conn = put_req_header(conn, "accept-encoding", "[gzip]")

      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/folder/hello_world.html"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200) |> :zlib.gunzip()
    end
  end

  describe "get_file_content/3" do
    setup do
      content = """
      {
        "error.html":{
          "encodage":"gzip",
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "gzip.js":{
          "encodage":"base64",
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "unsupported.xml":{
          "encodage":"unsupported",
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "raw.html":{
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "no_content.html":{
          "unsupported":"unsupported"
        },
        "image.png":{
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "ungzip.png":{
          "encodage":"gzip",
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        }
      }
      """

      content2 = """
      {
        "error.html":"4rdHFh%2BHYoS8oLdVvbUzEVqB8Lvm7kSPnuwF0AAABYQ%3D",
        "gzip.js":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg",
        "unsupported.xml":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg",
        "raw.html":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg",
        "no_content.html":"unsupported",
        "image.png":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg",
        "ungzip.png":"H4sIAAAAAAAAA7PJMLTzSM3JyVcozy_KSVFQtNEHigAA4YcXnxYAAAA"
      }
      """

      MockClient
      |> stub(:send_message, fn _, message, _ ->
        case message do
          %GetLastTransaction{} ->
            {:ok,
             %Transaction{
               address:
                 <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                   15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>,
               data: %TransactionData{content: content}
             }}

          %GetTransaction{} ->
            {:ok,
             %Transaction{
               data: %TransactionData{content: content2}
             }}
        end
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
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/gzip.js"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200)
    end

    test "should return gzipped file content", %{conn: conn} do
      conn = put_req_header(conn, "accept-encoding", "[gzip]")

      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/ungzip.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200) |> :zlib.gunzip()
    end

    test "should return ungzipped file content", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/ungzip.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200)
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

      assert "<h1>Hello world !</h1>" = response(conn1, 200)
      assert "<h1>Hello world !</h1>" = response(conn2, 200)
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
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/gzip.js"
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

  describe "get_file_content/3 with address_content" do
    setup do
      content = """
      {
        "address_content.png":{
          "encodage":"gzip",
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "concat_content.png":{
          "encodage":"gzip",
          "address":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de",
            "0000e363f156fc5185217433d986f59d9fe245226287c2dd94b1ac57ffb6df7928aa"
          ]
        }
      }
      """

      content2 = """
        {
          "concat_content.png":"H4sIAAAAAAAAA7PJMLTzSM3JyVcozy_",
          "address_content.png":"H4sIAAAAAAAAA7PJMLTzSM3JyVcozy_KSVFQtNEHigAA4YcXnxYAAAA"
        }
      """

      content3 = """
        {"concat_content.png":"KSVFQtNEHigAA4YcXnxYAAAA"}
      """

      MockClient
      |> stub(:send_message, fn _, message, _ ->
        case message do
          %GetLastTransaction{} ->
            {:ok,
             %Transaction{
               address:
                 <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                   15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>,
               data: %TransactionData{content: content}
             }}

          %GetTransaction{
            address:
              <<0, 0, 113, 251, 194, 32, 95, 62, 186, 57, 211, 16, 186, 241, 91, 216, 154, 1, 155,
                9, 41, 190, 118, 183, 134, 72, 82, 203, 104, 201, 205, 101, 2, 222>>
          } ->
            {:ok,
             %Transaction{
               data: %TransactionData{content: content2}
             }}

          %GetTransaction{
            address:
              <<0, 0, 227, 99, 241, 86, 252, 81, 133, 33, 116, 51, 217, 134, 245, 157, 159, 226,
                69, 34, 98, 135, 194, 221, 148, 177, 172, 87, 255, 182, 223, 121, 40, 170>>
          } ->
            {:ok,
             %Transaction{
               data: %TransactionData{content: content3}
             }}
        end
      end)

      :ok
    end

    test "should return content at specified addresses", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/address_content.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200)
    end

    test "should return concatened content at specified addresses", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/concat_content.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200)
    end
  end

  describe "get_cache/3" do
    test "should return 304 status if file is cached in browser", %{conn: conn} do
      content = """
      {
        "folder":{
          "hello_world.html":{
            "encodage":"base64",
            "address":[
              "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
            ]
          }
        }
      }
      """

      content2 = """
      {
        "folder":{
          "hello_world.html":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg"
        }
      }
      """

      MockClient
      |> stub(:send_message, fn _, message, _ ->
        case message do
          %GetLastTransaction{} ->
            {:ok,
             %Transaction{
               address:
                 <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                   15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>,
               data: %TransactionData{content: content}
             }}

          %GetTransaction{} ->
            {:ok,
             %Transaction{
               data: %TransactionData{content: content2}
             }}
        end
      end)

      conn1 =
        get(
          conn,
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/folder/hello_world.html"
        )

      etag = get_resp_header(conn1, "etag") |> Enum.at(0)

      assert "0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacbafolder/hello_world.html" =
               etag

      conn2 =
        get(
          conn |> put_req_header("if-none-match", etag),
          "/api/web_hosting/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/folder/hello_world.html"
        )

      assert "" = response(conn2, 304)
    end
  end
end
