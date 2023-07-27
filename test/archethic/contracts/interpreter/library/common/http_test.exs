defmodule Archethic.Contracts.Interpreter.Library.Common.HttpTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase, async: false
  alias Archethic.Contracts.Interpreter.Library.Common.Http

  doctest Http

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
      assert %{"status" => 200, "body" => "hello"} = Http.fetch("https://127.0.0.1:8081")
    end

    test "should return a 404 if domain does not exist" do
      assert %{"status" => 404, "body" => ""} = Http.fetch("https://localhost.local")
    end

    test "should return a 404 if page does not exist" do
      assert %{"status" => 404} = Http.fetch("https://127.0.0.1:8081/non-existing-page")
    end

    test "should return an error if endpoint is not HTTPS" do
      assert %{"status" => status, "body" => ""} = Http.fetch("http://127.0.0.1")
      assert status == Http.error_not_https()
    end

    test "should return an error if the result data is too large" do
      assert %{"status" => status, "body" => ""} =
               Http.fetch("https://127.0.0.1:8081/data?kbytes=260")

      assert status == Http.error_too_large()
    end

    test "should return an error if the endpoint is too slow" do
      assert %{"status" => status, "body" => ""} = Http.fetch("https://127.0.0.1:8081/very-slow")
      assert status == Http.error_timeout()
    end
  end

  describe "fetch_many/1" do
    test "should return an empty list if it receives an empty list" do
      assert [] = Http.fetch_many([])
    end

    test "should return a list with all kind of responses" do
      not_https_status = Http.error_not_https()
      timeout_status = Http.error_timeout()

      assert [
               %{"status" => 200},
               %{"status" => 404},
               %{"status" => 404},
               %{"status" => ^not_https_status},
               %{"status" => ^timeout_status}
             ] =
               Http.fetch_many([
                 "https://127.0.0.1:8081",
                 "https://localhost.local",
                 "https://127.0.0.1:8081/non-existing-page",
                 "http://127.0.0.1",
                 "https://127.0.0.1:8081/very-slow"
               ])
    end

    test "should return an error if there is more than 5 urls" do
      too_many_status = Http.error_too_many()

      assert [
               %{"status" => ^too_many_status},
               %{"status" => ^too_many_status},
               %{"status" => ^too_many_status},
               %{"status" => ^too_many_status},
               %{"status" => ^too_many_status},
               %{"status" => ^too_many_status}
             ] =
               Http.fetch_many([
                 "https://127.0.0.1:8081",
                 "https://127.0.0.1:8081",
                 "https://127.0.0.1:8081",
                 "https://127.0.0.1:8081",
                 "https://127.0.0.1:8081",
                 "https://127.0.0.1:8081"
               ])
    end

    test "should return an error if the combinaison of urls' body is too large" do
      too_large_status = Http.error_too_large()

      assert [
               %{"status" => ^too_large_status},
               %{"status" => ^too_large_status}
             ] =
               Http.fetch_many([
                 "https://127.0.0.1:8081/data?kbytes=200",
                 "https://127.0.0.1:8081/data?kbytes=200"
               ])
    end
  end
end
