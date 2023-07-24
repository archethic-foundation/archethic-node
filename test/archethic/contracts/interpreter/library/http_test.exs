defmodule Archethic.Contracts.Interpreter.Library.HttpTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Http

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Http

  # ----------------------------------------
  describe "fetch/1" do
    @tag :http
    test "should return a 200 with body when endpoint is OK" do
      code = ~S"""
      actions triggered_by: transaction do
        response = Http.fetch("https://baconipsum.com/api/?type=meat-and-filler&paras=5&format=text")
        if response.status == 200 do
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
        response = Http.fetch("https://archethic-archethic-archethic-archethic-archethic-archethic.net")
        if response.status == 404 do
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
        response = Http.fetch("https://www.archethic.net/hopefully-non-existing-page")
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
        response = Http.fetch("http://archethic.net")
        if response.status == #{Http.error_not_https()} do
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
        # this request return ~360KB which is bigger than 256KB threshold
        response = Http.fetch("https://fakerapi.it/api/v1/companies?_quantity=1000")
        if response.status == #{Http.error_too_large()} do
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
          "https://baconipsum.com/api/?type=meat-and-filler&paras=5&format=text",
          "https://archethic-archethic-archethic-archethic-archethic-archethic.net",
          "https://www.archethic.net/hopefully-non-existing-page",
          "http://archethic.net"
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
          "https://baconipsum.com/api/?type=meat-and-filler&paras=5&format=text",
          "https://baconipsum.com/api/?type=meat-and-filler&paras=5&format=text",
          "https://baconipsum.com/api/?type=meat-and-filler&paras=5&format=text",
          "https://baconipsum.com/api/?type=meat-and-filler&paras=5&format=text",
          "https://baconipsum.com/api/?type=meat-and-filler&paras=5&format=text",
          "https://baconipsum.com/api/?type=meat-and-filler&paras=5&format=text"
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
        # this request should return ~180KB
        # 2 of them cannot pass
        responses = Http.fetch_many([
          "https://fakerapi.it/api/v1/companies?_quantity=500",
          "https://fakerapi.it/api/v1/companies?_quantity=500"
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
