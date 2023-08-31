defmodule Archethic.Contracts.Interpreter.Library.Common.HttpImplTest do
  @moduledoc false
  use ArchethicCase, async: false

  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.Common.HttpImpl

  doctest HttpImpl

  setup_all do
    # start (once) a HTTPS server for our test
    {:ok, pid} =
      Supervisor.start_link(
        [
          {Plug.Cowboy,
           scheme: :https,
           plug: Archethic.MockServer,
           options: [
             otp_app: :archethic,
             port: 8081,
             keyfile: "priv/cert/selfsigned_key.pem",
             certfile: "priv/cert/selfsigned.pem"
           ]}
        ],
        strategy: :one_for_one,
        name: ArchethicHTTPTestSupervisor
      )

    on_exit(fn ->
      Process.exit(pid, :normal)
    end)

    :ok
  end

  # ----------------------------------------
  describe "fetch/1" do
    test "should return a 200 with body when endpoint is OK" do
      assert %{"status" => 200, "body" => "hello"} = HttpImpl.fetch("https://127.0.0.1:8081")
    end

    test "should raise if domain does not exist" do
      assert_raise Library.Error, fn -> HttpImpl.fetch("https://localhost.local") end
    end

    test "should return a 404 if page does not exist" do
      assert %{"status" => 404} = HttpImpl.fetch("https://127.0.0.1:8081/non-existing-page")
    end

    test "should raise if endpoint is not HTTPS" do
      assert_raise Library.Error, fn -> HttpImpl.fetch("http://127.0.0.1") end
    end

    test "should raise if the result data is too large" do
      assert_raise Library.Error, fn ->
        HttpImpl.fetch("https://127.0.0.1:8081/data?kbytes=260")
      end
    end

    test "should raise if the endpoint is too slow" do
      assert_raise Library.Error, fn -> HttpImpl.fetch("https://127.0.0.1:8081/very-slow") end
    end

    test "should raise if it's called more than once in the same process" do
      assert %{"status" => 200, "body" => "hello"} = HttpImpl.fetch("https://127.0.0.1:8081")
      assert_raise Library.Error, fn -> HttpImpl.fetch("https://127.0.0.1:8081") end
    end
  end

  describe "fetch_many/1" do
    test "should return an empty list if it receives an empty list" do
      assert [] = HttpImpl.fetch_many([])
    end

    test "should return a list with all kind of responses" do
      assert [
               %{"status" => 200},
               %{"status" => 404}
             ] =
               HttpImpl.fetch_many([
                 "https://127.0.0.1:8081",
                 "https://127.0.0.1:8081/non-existing-page"
               ])
    end

    test "should raise if there is at least 1 timeout" do
      assert_raise Library.Error, fn ->
        HttpImpl.fetch_many([
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081/very-slow"
        ])
      end
    end

    test "should raise if there is a wrong url" do
      assert_raise Library.Error, fn ->
        HttpImpl.fetch_many([
          "https://127.0.0.1:8081",
          "https://localhost.local"
        ])
      end

      assert_raise Library.Error, fn ->
        HttpImpl.fetch_many([
          "https://127.0.0.1:8081",
          "http://127.0.0.1"
        ])
      end
    end

    test "should raise if there is more than 5 urls" do
      assert_raise Library.Error, fn ->
        HttpImpl.fetch_many([
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081"
        ])
      end
    end

    test "should raise if the combinaison of urls' body is too large" do
      assert_raise Library.Error, fn ->
        HttpImpl.fetch_many([
          "https://127.0.0.1:8081/data?kbytes=200",
          "https://127.0.0.1:8081/data?kbytes=200"
        ])
      end
    end

    test "should raise if it's called more than once in the same process" do
      assert [%{"status" => 200, "body" => "hello"}] =
               HttpImpl.fetch_many(["https://127.0.0.1:8081"])

      assert_raise Library.Error, fn -> HttpImpl.fetch_many(["https://127.0.0.1:8081"]) end
    end
  end
end
