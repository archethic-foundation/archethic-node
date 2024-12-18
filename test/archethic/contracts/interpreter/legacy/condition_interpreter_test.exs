defmodule Archethic.Contracts.Interpreter.Legacy.ConditionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Conditions.Subjects, as: ConditionsSubjects
  alias Archethic.Contracts.Interpreter.Legacy.ConditionInterpreter
  alias Archethic.Contracts.Interpreter

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.FirstPublicKey
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.FirstTransactionAddress

  doctest ConditionInterpreter

  import Mox

  # seed for replacement address 7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3
  test "should parse map based inherit constraints" do
    assert {:ok, :inherit,
            %ConditionsSubjects{
              uco_transfers:
                {:==, _,
                 [
                   {:get_in, _,
                    [
                      {:scope, _, nil},
                      ["next", "uco_transfers"]
                    ]},
                   {:%{}, [line: 2],
                    [
                      {"0000C5EDE44A66D452EB6B27D6AA898C9FEF0A2E793207A5AFB2C566047D3BD5D3E8",
                       1_040_000_000}
                    ]}
                 ]}
            }} =
             """
             condition inherit: [
               uco_transfers: %{ "0000C5EDE44A66D452EB6B27D6AA898C9FEF0A2E793207A5AFB2C566047D3BD5D3E8" => 1040000000 }
             ]
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
  end

  test "should parse multiline inherit constraints" do
    assert {:ok, :inherit,
            %ConditionsSubjects{
              uco_transfers:
                {:==, _,
                 [
                   {:get_in, _, [{:scope, _, nil}, ["next", "uco_transfers"]]},
                   [
                     {:%{}, _,
                      [
                        {"to",
                         "0000C5EDE44A66D452EB6B27D6AA898C9FEF0A2E793207A5AFB2C566047D3BD5D3E8"},
                        {"amount", 1_040_000_000}
                      ]}
                   ]
                 ]},
              content: {:==, _, [{:get_in, _, [{:scope, _, nil}, ["next", "content"]]}, "hello"]}
            }} =
             """
               condition inherit: [
                 uco_transfers: [%{ to: "0000C5EDE44A66D452EB6B27D6AA898C9FEF0A2E793207A5AFB2C566047D3BD5D3E8", amount: 1040000000 }],
                 content: "hello"
               ]

             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
  end

  test "should flatten comparison operators" do
    assert {:ok, :inherit,
            %ConditionsSubjects{
              content:
                {:>=, [line: 2],
                 [
                   {{:., [line: 2],
                     [
                       {:__aliases__, [alias: Archethic.Contracts.Interpreter.Legacy.Library],
                        [:Library]},
                       :size
                     ]}, [line: 2],
                    [
                      {:get_in, [line: 2], [{:scope, [line: 2], nil}, ["next", "content"]]}
                    ]},
                   10
                 ]}
            }} =
             """
             condition inherit: [
               content: size() >= 10
             ]
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
  end

  test "should accept conditional code within condition" do
    assert {:ok, :inherit, %ConditionsSubjects{}} =
             ~S"""
             condition inherit: [
               content: if type == transfer do
                regex_match?("hello")
               else
                regex_match?("hi")
               end
             ]

             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
  end

  test "should accept different type of transaction keyword references" do
    assert {:ok, :inherit, %ConditionsSubjects{}} =
             ~S"""
              condition inherit: [
               content: if next.type == transfer do
                 "hi"
               else
                 if previous.type == transfer do
                   "hi"
                 else
                   "hello"
                 end
               end
              ]
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
  end

  test "parse invalid uco transfers type definition" do
    assert {:error,
            "must be a map or a code instruction starting by an comparator - uco_transfers"} =
             """
             condition inherit: [
               uco_transfers: [%{ "0000C5EDE44A66D452EB6B27D6AA898C9FEF0A2E793207A5AFB2C566047D3BD5D3E8" => 1040000000 }]
             ]
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
  end

  test "parse invalid token transfers type definition" do
    assert {:error,
            "must be a map or a code instruction starting by an comparator - token_transfers"} =
             """
             condition inherit: [
               token_transfers: [%{ "0000C5EDE44A66D452EB6B27D6AA898C9FEF0A2E793207A5AFB2C566047D3BD5D3E8" => 1040000000 }]
             ]
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
  end

  describe "valid_conditions?" do
    test "should validate complex if conditions" do
      {:ok, :inherit, conditions} =
        ~S"""
        condition inherit: [
          type: in?([transfer, token]),
          content: if type == transfer do
           regex_match?("reason transfer: (.*)")
          else
           regex_match?("reason token creation: (.*)")
          end
        ]
        """
        |> Interpreter.sanitize_code()
        |> elem(1)
        |> ConditionInterpreter.parse()

      assert true ==
               ConditionInterpreter.valid_conditions?(conditions, %{
                 "next" => %{"type" => "transfer", "content" => "reason transfer: pay back alice"}
               })

      assert false ==
               ConditionInterpreter.valid_conditions?(conditions, %{
                 "next" => %{"type" => "transfer", "content" => "dummy"}
               })

      assert true ==
               ConditionInterpreter.valid_conditions?(conditions, %{
                 "next" => %{
                   "type" => "token",
                   "content" => "reason token creation: new super token"
                 }
               })
    end

    test "shall get the genesis address of the chain in the conditions" do
      key = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: key,
        last_public_key: key,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>> |> Base.encode16()
      b_address = Base.decode16!(address)

      MockClient
      |> expect(:send_message, fn _, _, _ ->
        {:ok, %GenesisAddress{address: b_address, timestamp: DateTime.utc_now()}}
      end)

      assert true =
               ~s"""
               condition transaction: [
                 address: get_genesis_address() == "#{address}"
               ]
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse()
               |> elem(2)
               |> ConditionInterpreter.valid_conditions?(%{
                 "transaction" => %{
                   "address" => <<0::16, :crypto.strong_rand_bytes(32)::binary>>
                 }
               })
    end

    test "should get first tx address of the chain in the conditions" do
      key = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: key,
        last_public_key: key,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      address = "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4"
      b_address = Base.decode16!(address)

      MockClient
      |> expect(:send_message, 1, fn _, _, _ ->
        {:ok, %FirstTransactionAddress{address: b_address, timestamp: DateTime.utc_now()}}
      end)

      assert true =
               ~s"""
               condition transaction: [
                 address: get_first_transaction_address() == "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4"
               ]
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse()
               |> elem(2)
               |> ConditionInterpreter.valid_conditions?(%{
                 "transaction" => %{"address" => :crypto.strong_rand_bytes(32)}
               })
    end

    test "shall get the first public of the chain in the conditions" do
      key = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: key,
        last_public_key: key,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      public_key = "0001DDE54A313E5DCD73E413748CBF6679F07717F8BDC66CBE8F981E1E475A98605C"
      b_public_key = Base.decode16!(public_key)

      MockClient
      |> expect(:send_message, fn _, _, _ ->
        {:ok, %FirstPublicKey{public_key: b_public_key}}
      end)

      assert true =
               ~s"""
               condition transaction: [
                 previous_public_key: get_genesis_public_key() == "0001DDE54A313E5DCD73E413748CBF6679F07717F8BDC66CBE8F981E1E475A98605C"
               ]
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse()
               |> elem(2)
               |> ConditionInterpreter.valid_conditions?(%{
                 "transaction" => %{
                   "previous_public_key" => <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
                 }
               })
    end

    test "should return true if the ast of the code is the same" do
      assert ~s"""
             condition inherit: []
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "previous" => %{
                 "code" => ~s"""
                  condition inherit: [    ]
                 """
               },
               "next" => %{
                 "code" => ~s"""
                  condition inherit: []


                 """
               }
             })
    end

    test "should return false if the ast of the code is the different" do
      refute ~s"""
             condition inherit: []
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "previous" => %{
                 "code" => ~s"""
                  condition inherit: [    ]
                 """
               },
               "next" => %{
                 "code" => ~s"""
                  condition inherit: [1]
                 """
               }
             })
    end

    test "should validate condition on uco_transfers size" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      assert Interpreter.sanitize_code(~s"""
             condition transaction: [
               uco_transfers: size() < 10
             ]
             """)
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "transaction" => %{
                 "uco_transfers" => %{"#{address}" => 12}
               }
             })
    end

    test "should invalidate condition on uco_transfers size" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      refute Interpreter.sanitize_code(~s"""
             condition transaction: [
               uco_transfers: size() > 10
             ]
             """)
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "transaction" => %{
                 "uco_transfers" => %{"#{address}" => 12}
               }
             })
    end

    test "should validate oracle condition" do
      assert Interpreter.sanitize_code(~s"""
             condition oracle: [
               content: json_path_extract(\"$.uco.eur\") > 1
             ]
             """)
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "transaction" => %{
                 "content" => Jason.encode!(%{uco: %{eur: 2}})
               }
             })
    end
  end
end
