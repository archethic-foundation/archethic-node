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
  describe "request/4 common behavior" do
    test "should raise if domain does not exist" do
      assert_raise Library.Error, fn -> HttpImpl.request("https://localhost.local", "GET") end
    end

    test "should return a 404 if page does not exist" do
      assert %{"status" => 404} =
               HttpImpl.request("https://127.0.0.1:8081/non-existing-page", "GET")
    end

    test "should raise if endpoint is not HTTPS" do
      assert_raise Library.Error, fn -> HttpImpl.request("http://127.0.0.1", "GET") end
    end

    test "should raise if the result data is too large" do
      assert_raise Library.Error, fn ->
        HttpImpl.request("https://127.0.0.1:8081/data?kbytes=260", "GET")
      end
    end

    test "should raise if the endpoint is too slow" do
      assert_raise Library.Error, fn ->
        HttpImpl.request("https://127.0.0.1:8081/very-slow", "GET")
      end
    end

    test "should raise if it's called more than once in the same process" do
      assert %{"status" => 200, "body" => "hello"} =
               HttpImpl.request("https://127.0.0.1:8081", "GET")

      assert_raise Library.Error, fn -> HttpImpl.request("https://127.0.0.1:8081", "GET") end
    end

    test "should raise if method is invalid" do
      assert_raise Library.Error, fn -> HttpImpl.request("https://127.0.0.1:8081", "INVALID") end
    end

    test "should raise if headers is invalid format" do
      assert_raise Library.Error, fn ->
        HttpImpl.request("https://127.0.0.1:8081", "GET", %{1 => "value"})
      end
    end
  end

  describe "request/4 with GET request" do
    test "should return a 200 with body when endpoint is OK" do
      assert %{"status" => 200, "body" => "hello"} =
               HttpImpl.request("https://127.0.0.1:8081", "GET")
    end
  end

  describe "request/4 with POST request" do
    test "should return a 200 with parameter and headers filled" do
      params = %{"method" => "string", "value" => "something that will be returned"}
      headers = %{"Content-Type" => "application/json"}

      assert %{"status" => 200, "body" => "something that will be returned"} =
               HttpImpl.request(
                 "https://127.0.0.1:8081/api",
                 "POST",
                 headers,
                 Jason.encode!(params)
               )
    end

    test "should return a 200 with error string if headers not set for application/json" do
      params = %{"method" => "string", "value" => "something that will be returned"}

      assert %{"status" => 200, "body" => "error"} =
               HttpImpl.request("https://127.0.0.1:8081/api", "POST", %{}, Jason.encode!(params))
    end
  end

  describe "request/5" do
    test "should return a status -4001 for timeout" do
      assert %{"status" => -4001} =
               HttpImpl.request("https://127.0.0.1:8081/very-slow", "GET", %{}, nil, false)
    end

    test "should return a status -4004 for non https" do
      assert %{"status" => -4004} =
               HttpImpl.request("http://127.0.0.1:8081/", "GET", %{}, nil, false)
    end

    test "should return a status -4002 for too large" do
      assert %{"status" => -4002} =
               HttpImpl.request("https://127.0.0.1:8081/data?kbytes=300", "GET", %{}, nil, false)
    end

    test "should return a status -4005 if it's already called once" do
      assert %{"status" => 200} =
               HttpImpl.request("https://127.0.0.1:8081", "GET", %{}, nil, false)

      assert %{"status" => -4005} =
               HttpImpl.request("https://127.0.0.1:8081", "GET", %{}, nil, false)
    end

    test "should return a -4001 if the domain is inexistant" do
      assert %{"status" => -4001} =
               HttpImpl.request("https://localhost.local", "GET", %{}, nil, false)
    end
  end

  describe "request_many/1" do
    test "should return an empty list if it receives an empty list" do
      assert [] = HttpImpl.request_many([])
    end

    test "should return a list with all kind of responses" do
      params = %{"method" => "string", "value" => "Hello world !"}
      headers = %{"Content-Type" => "application/json"}

      requests = [
        %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
        %{"url" => "https://127.0.0.1:8081/non-existing-page", "method" => "GET"},
        %{
          "url" => "https://127.0.0.1:8081/api",
          "method" => "POST",
          "headers" => headers,
          "body" => Jason.encode!(params)
        }
      ]

      assert [
               %{"status" => 200},
               %{"status" => 404},
               %{"status" => 200, "body" => "Hello world !"}
             ] = HttpImpl.request_many(requests)
    end

    test "should raise if there is at least 1 timeout" do
      assert_raise Library.Error, fn ->
        HttpImpl.request_many([
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
          %{"url" => "https://127.0.0.1:8081/very-slow", "method" => "GET"}
        ])
      end
    end

    test "should raise if there is a wrong url" do
      assert_raise Library.Error, fn ->
        HttpImpl.request_many([
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
          %{"url" => "https://localhost.local", "method" => "GET"}
        ])
      end

      assert_raise Library.Error, fn ->
        HttpImpl.request_many([
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
          %{"url" => "http://127.0.0.1", "method" => "GET"}
        ])
      end
    end

    test "should raise if there is more than 5 urls" do
      assert_raise Library.Error, fn ->
        HttpImpl.request_many([
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
          %{"url" => "https://127.0.0.1:8081", "method" => "GET"}
        ])
      end
    end

    test "should raise if the combinaison of urls' body is too large" do
      assert_raise Library.Error, fn ->
        HttpImpl.request_many([
          %{"url" => "https://127.0.0.1:8081/data?kbytes=200", "method" => "GET"},
          %{"url" => "https://127.0.0.1:8081/data?kbytes=200", "method" => "GET"}
        ])
      end
    end

    test "should raise if it's called more than once in the same process" do
      assert [%{"status" => 200, "body" => "hello"}] =
               HttpImpl.request_many([%{"url" => "https://127.0.0.1:8081", "method" => "GET"}])

      assert_raise Library.Error, fn ->
        HttpImpl.request_many([%{"url" => "https://127.0.0.1:8081", "method" => "GET"}])
      end
    end
  end

  describe "request_many/2" do
    test "should return a status -4001 for timeout" do
      assert [
               %{"status" => 200},
               %{"status" => -4001}
             ] =
               HttpImpl.request_many(
                 [
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081/very-slow", "method" => "GET"}
                 ],
                 false
               )
    end

    test "should return a status -4004 for non https" do
      assert [
               %{"status" => 200},
               %{"status" => -4004}
             ] =
               HttpImpl.request_many(
                 [
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "http://127.0.0.1", "method" => "GET"}
                 ],
                 false
               )
    end

    test "should return a status -4003 for too many urls" do
      assert [
               %{"status" => 200},
               %{"status" => 200},
               %{"status" => 200},
               %{"status" => 200},
               %{"status" => 200},
               %{"status" => -4003}
             ] =
               HttpImpl.request_many(
                 [
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"}
                 ],
                 false
               )
    end

    test "should return a status -4002 for too large" do
      assert [
               %{"status" => -4002},
               %{"status" => -4002}
             ] =
               HttpImpl.request_many(
                 [
                   %{"url" => "https://127.0.0.1:8081/data?kbytes=200", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081/data?kbytes=200", "method" => "GET"}
                 ],
                 false
               )
    end

    test "should return a status -4005 if it's already called once" do
      assert [%{"status" => 200}] =
               HttpImpl.request_many(
                 [%{"url" => "https://127.0.0.1:8081", "method" => "GET"}],
                 false
               )

      assert [%{"status" => -4005}, %{"status" => -4005}, %{"status" => -4005}] =
               HttpImpl.request_many(
                 [
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"}
                 ],
                 false
               )
    end

    test "should return a -4001 if the domain is inexistant" do
      assert [%{"status" => 200}, %{"status" => -4001}] =
               HttpImpl.request_many(
                 [
                   %{"url" => "https://127.0.0.1:8081", "method" => "GET"},
                   %{"url" => "https://localhost.local", "method" => "GET"}
                 ],
                 false
               )
    end
  end
end
