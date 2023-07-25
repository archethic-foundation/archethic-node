defmodule Archethic.Contracts.Interpreter.Library.HttpTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase, async: false
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Http

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

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
    @tag :http
    test "should return a 200 with body when endpoint is OK" do
      code = ~S"""
      actions triggered_by: transaction do
        response = Http.fetch("https://127.0.0.1:8081")
        if response.status == 200 && response.body == "hello" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    @tag :http
    test "should return a 404 if domain does not exist" do
      code = ~S"""
      actions triggered_by: transaction do
        response = Http.fetch("https://localhost.local")
        if response.status == 404 && response.body == "" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    @tag :http
    test "should return a 404 if page does not exist" do
      code = ~S"""
      actions triggered_by: transaction do
        response = Http.fetch("https://127.0.0.1:8081/non-existing-page")
        if response.status == 404 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    @tag :http
    test "should return an error if endpoint is not HTTPS" do
      code = ~s"""
      actions triggered_by: transaction do
        response = Http.fetch("http://127.0.0.1")
        if response.status == #{Http.error_not_https()} && response.body == "" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    @tag :http
    test "should return an error if the result data is too large" do
      code = ~s"""
      actions triggered_by: transaction do
        response = Http.fetch("https://127.0.0.1:8081/data?kbytes=260")
        if response.status == #{Http.error_too_large()} && response.body == "" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    @tag :http
    test "should return an error if the endpoint is too slow" do
      code = ~s"""
      actions triggered_by: transaction do
        response = Http.fetch("https://127.0.0.1:8081/very-slow")
        if response.status == #{Http.error_timeout()} && response.body == "" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  describe "fetch_many/1" do
    @tag :http
    test "should return an empty list if it receives an empty list" do
      code = ~S"""
      actions triggered_by: transaction do
        responses = Http.fetch_many([])
        if responses == [] do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    @tag :http
    test "should return a list with all kind of responses" do
      code = ~s"""
      actions triggered_by: transaction do
        responses = Http.fetch_many([
          "https://127.0.0.1:8081",
          "https://localhost.local",
          "https://127.0.0.1:8081/non-existing-page",
          "http://127.0.0.1"
        ])

        statuses = []
        for r in responses do
          statuses = List.append(statuses, r.status)
        end

        if statuses == [200, 404, 404, #{Http.error_not_https()}] do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    @tag :http
    test "should return an error if there is more than 5 urls" do
      code = ~s"""
      actions triggered_by: transaction do
        responses = Http.fetch_many([
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081",
          "https://127.0.0.1:8081"
        ])

        statuses = []
        for r in responses do
          statuses = List.append(statuses, r.status)
        end

        if statuses == [
          #{Http.error_too_many()},
          #{Http.error_too_many()},
          #{Http.error_too_many()},
          #{Http.error_too_many()},
          #{Http.error_too_many()},
          #{Http.error_too_many()}] do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    @tag :http
    test "should return an error if the combinaison of urls' body is too large" do
      code = ~s"""
      actions triggered_by: transaction do
        responses = Http.fetch_many([
          "https://127.0.0.1:8081/data?kbytes=200",
          "https://127.0.0.1:8081/data?kbytes=200"
        ])
        statuses = []
        for r in responses do
          statuses = List.append(statuses, r.status)
        end

        if statuses == [#{Http.error_too_large()}, #{Http.error_too_large()}] do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end
end
