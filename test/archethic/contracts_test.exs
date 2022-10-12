defmodule Archethic.ContractsTest do
  use ExUnit.Case

  alias Archethic.Contracts

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.Conditions
  alias Archethic.Contracts.Contract.Constants
  alias Archethic.Contracts.Contract.Trigger

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
      code = """
      condition inherit: [
        content: regex_match?("hello"),
        uco_transfers: %{
          "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9" => 1000000000
        },
        type: transfer
      ]

      actions triggered_by: transaction do
        add_uco_transfer to: "\3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9", amount: 1000000000
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

      actions triggered_by: interval, at: "0 * * * * *" do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 1000000000
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      {:ok, time} = DateTime.new(~D[2016-05-24], ~T[13:26:20], "Etc/UTC")

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

      assert false == Contracts.accept_new_contract?(previous_tx, next_tx, time)
    end

    test "should return false when the transaction have been triggered by interval and the timestamp does match " do
      code = """
      condition inherit: [
        uco_transfers: %{ "3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9" =>  1000000000}
      ]

      actions triggered_by: interval, at: "0 * * * * *" do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 1000000000
      end
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

      assert true == Contracts.accept_new_contract?(previous_tx, next_tx, time)
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
end
