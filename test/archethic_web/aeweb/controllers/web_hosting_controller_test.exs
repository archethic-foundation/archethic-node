defmodule ArchethicWeb.AEWeb.WebHostingControllerTest do
  use ArchethicCase, async: false
  use ArchethicWeb.ConnCase

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Crypto

  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Utils

  alias ArchethicCache.LRU
  alias ArchethicCache.LRUDisk

  import Mox
  import ArchethicCase

  setup do
    # There is a setup in ArchethicCase that removes the mut_dir()
    # Since we need it for LRUDisk, we recreate it on every test
    File.mkdir_p!(Path.join([Utils.mut_dir(), "aeweb", "web_hosting_cache_file"]))

    # clear cache on every test because most tests use the same address
    # and cache is a global state
    :ok = LRU.purge(:web_hosting_cache_ref_tx)
    :ok = LRUDisk.purge(:web_hosting_cache_file)

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
    test "should return 410 when unpublished", %{conn: conn} do
      address = random_address()
      address_hex = Base.encode16(address)

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: ^address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _, %GetTransaction{address: ^address}, _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{
               content: """
               {
                 "aewebVersion": 1,
                 "publicationStatus": "UNPUBLISHED"
               }
               """
             },
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}
      end)

      conn1 = get(conn, "/aeweb/#{address_hex}/")
      assert "Website has been unpublished" = response(conn1, 410)
    end

    test "should return Invalid address", %{conn: conn} do
      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _, %GetTransaction{}, _ ->
          {:error, :transaction_not_exists}
      end)

      conn1 = get(conn, "/aeweb/AZERTY/")
      conn2 = get(conn, "/aeweb/0123456789/")

      assert "Invalid address" = response(conn1, 400)
      assert "Invalid address" = response(conn2, 400)
    end

    test "should return Invalid transaction content", %{conn: conn} do
      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _, %GetTransaction{}, _ ->
          {:ok,
           %Transaction{
             address:
               <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                 15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>,
             data: %TransactionData{content: "invalid"},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}
      end)

      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/"
        )

      assert "Invalid transaction content" = response(conn, 400)
    end
  end

  describe "get_file/2" do
    setup do
      content = """
      {"aewebVersion": 1,
      "hashFunction": "sha-1",
      "metaData":{
        "index.html":{
          "encoding":"base64",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "folder/hello_world.html":{
          "encoding":"base64",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        }
      }
      }
      """

      content2 = """
      {
        "index.html":"PGgxPkFyY2hldGhpYzwvaDE-",
        "folder/hello_world.html":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg"
      }
      """

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _,
        %GetTransaction{
          address:
            address =
                <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                  15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>
        },
        _ ->
          {:ok,
           %Transaction{
             address: address,
             data: %TransactionData{content: content},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}

        _,
        %GetTransaction{
          address:
            <<0, 0, 113, 251, 194, 32, 95, 62, 186, 57, 211, 16, 186, 241, 91, 216, 154, 1, 155,
              9, 41, 190, 118, 183, 134, 72, 82, 203, 104, 201, 205, 101, 2, 222>>
        },
        _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{content: content2},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}
      end)

      :ok
    end

    test "should return index.html on file not found (handle JS routing)", %{conn: conn} do
      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/file.html"
        )

      assert "<h1>Archethic</h1>" = response(conn, 200)
    end

    test "should return default index.html file", %{conn: conn} do
      conn = put_req_header(conn, "accept-encoding", "[gzip]")

      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/"
        )

      assert "<h1>Archethic</h1>" = response(conn, 200) |> :zlib.gunzip()
    end

    test "should return selected file", %{conn: conn} do
      conn = put_req_header(conn, "accept-encoding", "[gzip]")

      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/folder/hello_world.html"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200) |> :zlib.gunzip()
    end
  end

  describe "get_file_content/3" do
    setup do
      content = """
      {
        "aewebVersion": 1,
      "hashFunction": "sha-1",
      "metaData":{
        "error.html":{
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "gzip.js":{
          "encoding":"base64",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "unsupported.xml":{
          "encoding":"unsupported",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "raw.html":{
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "no_content.html":{
          "unsupported":"unsupported"
        },
        "image.png":{
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "IMAGE2.png":{
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "ungzip.png":{
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        }
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
        "IMAGE2.png":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg",
        "ungzip.png":"H4sIAAAAAAAAA7PJMLTzSM3JyVcozy_KSVFQtNEHigAA4YcXnxYAAAA"
      }
      """

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _,
        %GetTransaction{
          address:
            address =
                <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                  15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>
        },
        _ ->
          {:ok,
           %Transaction{
             address: address,
             data: %TransactionData{content: content},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}

        _,
        %GetTransaction{
          address:
            <<0, 0, 113, 251, 194, 32, 95, 62, 186, 57, 211, 16, 186, 241, 91, 216, 154, 1, 155,
              9, 41, 190, 118, 183, 134, 72, 82, 203, 104, 201, 205, 101, 2, 222>>
        },
        _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{content: content2},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}
      end)

      :ok
    end

    test "should return Invalid file encoding", %{conn: conn} do
      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/error.html"
        )

      assert "Invalid file encoding" = response(conn, 400)
    end

    test "should return Cannot find file content", %{conn: conn} do
      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/no_content.html"
        )

      assert "Cannot find file content" = response(conn, 404)
    end

    test "should return decoded file content", %{conn: conn} do
      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/gzip.js"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200)
    end

    test "should return gzipped file content", %{conn: conn} do
      conn = put_req_header(conn, "accept-encoding", "[gzip]")

      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/ungzip.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200) |> :zlib.gunzip()
    end

    test "should return ungzipped file content", %{conn: conn} do
      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/ungzip.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200)
    end

    test "should downcase url_path before processing", %{conn: conn} do
      conn1 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/IMage.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn1, 200)

      conn2 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/image2.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn2, 200)

      conn3 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/image.jpeg"
        )

      assert "Cannot find file content" = response(conn3, 404)
    end

    test "should return raw file content", %{conn: conn} do
      conn1 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/raw.html"
        )

      conn2 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/unsupported.xml"
        )

      assert "<h1>Hello world !</h1>" = response(conn1, 200)
      assert "<h1>Hello world !</h1>" = response(conn2, 200)
    end

    test "should return good file content-type", %{conn: conn} do
      conn1 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/raw.html"
        )

      conn2 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/unsupported.xml"
        )

      conn3 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/gzip.js"
        )

      conn4 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/image.png"
        )

      assert ["text/html; charset=utf-8"] = get_resp_header(conn1, "content-type")
      assert ["text/xml; charset=utf-8"] = get_resp_header(conn2, "content-type")
      assert ["text/javascript; charset=utf-8"] = get_resp_header(conn3, "content-type")
      assert ["image/png; charset=utf-8"] = get_resp_header(conn4, "content-type")
    end
  end

  describe "should return a directory listing if there is no index.html file" do
    setup do
      content = """
      {
        "aewebVersion": 1,
      "hashFunction": "sha-1",
      "metaData":{
        "dir1/file10.txt":{
          "size": 10,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "dir1/file11.txt":{
          "size": 10,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "dir2/hello.txt":{
          "size": 10,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "dir3/index.html":{
          "size": 10,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "file1.txt":{
          "size": 10,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "file2.txt":{
          "size": 10,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "file3.txt":{
          "size": 10,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        }
      }
      }
      """

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _, %GetTransaction{address: address}, _ ->
          {:ok,
           %Transaction{
             address: address,
             data: %TransactionData{content: content},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}
      end)

      :ok
    end

    test "should return a directory listing", %{conn: conn} do
      # directory listing at root
      conn1 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/"
        )

      # directory listing in a sub folder with trailing /
      conn2 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/dir1/"
        )

      # directory listing in a sub folder w/o trailing /
      conn3 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/dir1"
        )

      html1 = response(conn1, 200)
      html2 = response(conn2, 200)
      html3 = response(conn3, 200)
      assert String.contains?(html1, "Index of")
      assert String.contains?(html2, "Index of")
      assert String.contains?(html3, "Index of")
    end
  end

  describe "get_file_content/3 with address_content" do
    setup do
      content = """
      {"aewebVersion": 1,
      "hashFunction": "sha-1",
      "metaData":{
        "address_content.png":{
          "size": 20,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        },
        "concat_content.png":{
          "size": 30,
          "encoding":"gzip",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de",
            "0000e363f156fc5185217433d986f59d9fe245226287c2dd94b1ac57ffb6df7928aa"
          ]
        }
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
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _,
        %GetTransaction{
          address:
            address =
                <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                  15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>
        },
        _ ->
          {:ok,
           %Transaction{
             address: address,
             data: %TransactionData{content: content},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}

        _,
        %GetTransaction{
          address:
            <<0, 0, 113, 251, 194, 32, 95, 62, 186, 57, 211, 16, 186, 241, 91, 216, 154, 1, 155,
              9, 41, 190, 118, 183, 134, 72, 82, 203, 104, 201, 205, 101, 2, 222>>
        },
        _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{content: content2},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}

        _,
        %GetTransaction{
          address:
            <<0, 0, 227, 99, 241, 86, 252, 81, 133, 33, 116, 51, 217, 134, 245, 157, 159, 226, 69,
              34, 98, 135, 194, 221, 148, 177, 172, 87, 255, 182, 223, 121, 40, 170>>
        },
        _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{content: content3},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}
      end)

      :ok
    end

    test "should return content at specified addresses", %{conn: conn} do
      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/address_content.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200)
    end

    test "should return concatened content at specified addresses", %{conn: conn} do
      conn =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/concat_content.png"
        )

      assert "<h1>Hello world !</h1>" = response(conn, 200)
    end
  end

  describe "get_cache/3" do
    test "should return 304 status if file is cached in browser", %{conn: conn} do
      content = """
      {"aewebVersion": 1,
      "hashFunction": "sha-1",
      "metaData":{
        "folder/hello_world.html":{
          "size": 20,
          "encoding":"base64",
          "addresses":[
            "000071fbc2205f3eba39d310baf15bd89a019b0929be76b7864852cb68c9cd6502de"
          ]
        }

      }
      }
      """

      content2 = """
      {
        "folder/hello_world.html":"PGgxPkhlbGxvIHdvcmxkICE8L2gxPg"
      }
      """

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _,
        %GetTransaction{
          address:
            address =
                <<0, 0, 34, 84, 150, 163, 128, 213, 0, 92, 182, 131, 116, 233, 184, 180, 93, 126,
                  15, 80, 90, 66, 248, 205, 97, 203, 212, 60, 54, 132, 197, 203, 172, 186>>
        },
        _ ->
          {:ok,
           %Transaction{
             address: address,
             data: %TransactionData{content: content},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}

        _,
        %GetTransaction{
          address:
            <<0, 0, 113, 251, 194, 32, 95, 62, 186, 57, 211, 16, 186, 241, 91, 216, 154, 1, 155,
              9, 41, 190, 118, 183, 134, 72, 82, 203, 104, 201, 205, 101, 2, 222>>
        },
        _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{content: content2},
             validation_stamp: %ValidationStamp{
               timestamp: DateTime.utc_now()
             }
           }}
      end)

      conn1 =
        get(
          conn,
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/folder/hello_world.html"
        )

      etag = get_resp_header(conn1, "etag") |> Enum.at(0)

      assert "0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacbafolder/hello_world.html" =
               etag

      conn2 =
        get(
          conn |> put_req_header("if-none-match", etag),
          "/aeweb/0000225496a380d5005cb68374e9b8b45d7e0f505a42f8cd61cbd43c3684c5cbacba/folder/hello_world.html"
        )

      assert "" = response(conn2, 304)
    end
  end
end
