defmodule Archethic.ContractsTest do
  use ExUnit.Case

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.Interpreter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  @moduletag capture_log: true

  doctest Contracts

  describe "accept_new_contract?/3" do
    test "should return false when the inherit constraints literal values are not respected" do
      code = """
      condition inherit: [
        uco_transfers: [%{ to: "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9", amount: 1000000000}],
        content: "hello"
      ]

      condition transaction: []

      actions triggered_by: transaction do
        add_uco_transfer to: "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9", amount: 1000000000
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 20.0
                }
              ]
            }
          }
        }
      }

      assert false == Contracts.accept_new_contract?(previous_tx, next_tx, DateTime.utc_now())
    end

    test "should return false when the inherit constraints execution return false" do
      code = """
      condition inherit: [
        content: regex_match?(\"hello\")
      ]

      condition transaction: []

      actions triggered_by: transaction do
        set_content "hello"
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        data: %TransactionData{
          code: code,
          content: "hola"
        }
      }

      assert false == Contracts.accept_new_contract?(previous_tx, next_tx, DateTime.utc_now())
    end

    test "should return true when the inherit constraints matches the next transaction" do
      address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      condition inherit: [
        content: regex_match?("hello"),
        uco_transfers: %{"#{Base.encode16(address)}" => 1000000000},
        type: transfer
      ]

      condition transaction: []

      actions triggered_by: transaction do
        add_uco_transfer to: "#{Base.encode16(address)}", amount: 1000000000
        set_content "hello"
        set_type transfer
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{
          code: code,
          content: "hello",
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to: address,
                  amount: 1_000_000_000
                }
              ]
            }
          }
        }
      }

      assert true == Contracts.accept_new_contract?(previous_tx, next_tx, DateTime.utc_now())
    end

    test "should return false when the transaction have been triggered by datetime but timestamp doesn't match " do
      time = DateTime.utc_now() |> DateTime.to_unix()

      code = """
      condition inherit: [
        uco_transfers: %{ "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9" =>  1000000000}
      ]

      actions triggered_by: datetime, at: #{time} do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 1000000000
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 1_000_000_000
                }
              ]
            }
          }
        }
      }

      assert false ==
               Contracts.accept_new_contract?(
                 previous_tx,
                 next_tx,
                 DateTime.utc_now() |> DateTime.add(10)
               )
    end

    test "should return true when the transaction have been triggered by datetime and the timestamp does match " do
      ref_time = DateTime.utc_now()

      code = """
      condition inherit: [
        uco_transfers: %{ "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9" => 1000000000 }
      ]

      actions triggered_by: datetime, at: #{DateTime.to_unix(ref_time)} do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 1000000000
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 1_000_000_000
                }
              ]
            }
          }
        }
      }

      assert true == Contracts.accept_new_contract?(previous_tx, next_tx, ref_time)
    end

    test "should return false when the transaction have been triggered by interval but timestamp doesn't match " do
      code = """
      condition inherit: [
        uco_transfers: %{ "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9" => 1000000000}
      ]

      actions triggered_by: interval, at: "0 * * * *" do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 1000000000
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 1_000_000_000
                }
              ]
            }
          }
        }
      }

      assert false ==
               Contracts.accept_new_contract?(previous_tx, next_tx, ~U[2016-05-24 13:26:20Z])
    end

    test "should return false when the transaction have been triggered by interval and the timestamp does match " do
      code = """
      condition inherit: [
        uco_transfers: %{ "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9" =>  1000000000}
      ]

      actions triggered_by: interval, at: "0 * * * *" do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 1000000000
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 1_000_000_000
                }
              ]
            }
          }
        }
      }

      assert true ==
               Contracts.accept_new_contract?(previous_tx, next_tx, ~U[2016-05-24 13:00:00Z])
    end

    test "should return true when the inherit constraint match and when no trigger is specified" do
      code = """
      condition inherit: [
        content: "hello"
      ]
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      {:ok, time} = DateTime.new(~D[2016-05-24], ~T[13:26:00.000999], "Etc/UTC")

      next_tx = %Transaction{
        data: %TransactionData{
          code: code,
          content: "hello"
        }
      }

      assert true == Contracts.accept_new_contract?(previous_tx, next_tx, time)
    end
  end

  test "case behavior is similar in legacy and current interpreter" do
    contract_tx = %Transaction{
      data: %TransactionData{
        code: """
        @version 1
        condition inherit: []
        condition transaction: [
          content: Crypto.hash() == "3c3b183c50f8a3731582ec624af96a67e5254934146c19fb5415e0c3a83d9ba0"
        ]
        """
      }
    }

    contract_legacy_tx = %Transaction{
      data: %TransactionData{
        code: """
        condition inherit: []
        condition transaction: [
          content: hash() == "3c3b183c50f8a3731582ec624af96a67e5254934146c19fb5415e0c3a83d9ba0"
        ]
        """
      }
    }

    trigger_tx = %Transaction{
      type: :data,
      data: %TransactionData{
        content: "Han shot first"
      }
    }

    contract = Contract.from_transaction!(contract_tx)
    contract_legacy = Contract.from_transaction!(contract_legacy_tx)

    # will be transformed into Contracts.valid_conditions? in 1.2.0
    assert Interpreter.valid_conditions?(0, contract_legacy.conditions.transaction, %{
             "transaction" => Constants.from_transaction(trigger_tx),
             "contract" => contract_legacy.constants.contract
           })

    assert Interpreter.valid_conditions?(1, contract.conditions.transaction, %{
             "transaction" => Constants.from_transaction(trigger_tx),
             "contract" => contract.constants.contract
           })
  end
end
