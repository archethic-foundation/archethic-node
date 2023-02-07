defmodule Archethic.Contracts.Interpreter.Version1Test do
  use ArchethicCase

  @version {1, 0, 0}

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Interpreter.Version1

  doctest Version1

  describe "parse/1" do
    # test "should return an error if no conditions or no triggers are defined" do
    #   assert {:error, _} =
    #            ~S"""
    #            condition inherit: [
    #             content: true
    #            ]
    #            """
    #            |> Version1.parse(@version)

    #   assert {:error, _} =
    #            """
    #            actions triggered_by: transaction do
    #             set_content "hello"
    #            end
    #            """
    #            |> Version1.parse(@version)
    # end

    # test "should return an error if there are unexpected terms" do
    #   assert {:error, _} =
    #            """
    #            condition transaction: [
    #             uco_transfers: Map.size() > 0
    #            ]

    #            some_code

    #            actions triggered_by: transaction do
    #             set_content "hello"
    #            end
    #            """
    #            |> Version1.parse(@version)
    # end

    # test "should return the contract if format is OK" do
    #   assert {:ok, %Contract{}} =
    #            """
    #            condition transaction: [
    #             uco_transfers: Map.size() > 0
    #            ]

    #            actions triggered_by: transaction do
    #             Contract.set_content "hello"
    #            end
    #            """
    #            |> Version1.parse(@version)
    # end
  end
end
