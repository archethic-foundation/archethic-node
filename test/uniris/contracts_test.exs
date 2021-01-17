defmodule Uniris.ContractsTest do
  use ExUnit.Case

  alias Uniris.Contracts

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Contract.Conditions
  alias Uniris.Contracts.Contract.Constants
  alias Uniris.Contracts.Contract.Trigger

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

  @moduletag capture_log: true

  doctest Contracts

  describe "accept_new_contract?/2" do
    test "should return false the inherit constraints are not respected" do
      code = """
      condition inherit: next_transaction.uco_transfers[\"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\"] == 10.0
      actions triggered_by: transaction do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 10.0
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

      assert false == Contracts.accept_new_contract?(previous_tx, next_tx)
    end

    test "should return false when the transaction did not execute not the previous code" do
      code = """
      condition inherit: next_transaction.uco_transfers["3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9"] == 10.0
      actions triggered_by: transaction do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 10.0
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
                    <<36, 242, 49, 41, 137, 161, 190, 247, 130, 61, 197, 163, 108, 217, 83, 240,
                      157, 82, 207, 212, 36, 42, 196, 144, 161, 229, 16, 5, 9, 166, 4, 94>>,
                  amount: 5.0
                },
                %Transfer{
                  to:
                    <<75, 142, 249, 164, 52, 167, 16, 63, 135, 197, 12, 163, 14, 6, 190, 71, 113,
                      173, 172, 71, 168, 203, 207, 79, 137, 95, 45, 217, 22, 107, 103, 147>>,
                  amount: 5.0
                }
              ]
            }
          }
        }
      }

      assert false == Contracts.accept_new_contract?(previous_tx, next_tx)
    end

    test "should return true when the transaction from the contract is valid" do
      code = """
      condition inherit: next_transaction.uco_transfers[\"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\"] == 10.0
      actions triggered_by: transaction do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 10.0
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
                  amount: 10.0
                }
              ]
            }
          }
        }
      }

      assert true == Contracts.accept_new_contract?(previous_tx, next_tx)
    end

    test "should return false when the transaction have been triggered by datetime but timestamp doesn't match " do
      time = DateTime.utc_now() |> DateTime.to_unix()

      code = """
      condition inherit: next_transaction.uco_transfers[\"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\"] == 10.0
      actions triggered_by: datetime, at: #{time} do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 10.0
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        timestamp: DateTime.utc_now() |> DateTime.add(10),
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 10.0
                }
              ]
            }
          }
        }
      }

      assert false == Contracts.accept_new_contract?(previous_tx, next_tx)
    end

    test "should return true when the transaction have been triggered by datetime and the timestamp does match " do
      ref_time = DateTime.utc_now()

      code = """
      condition inherit: next_transaction.uco_transfers[\"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\"] == 10.0
      actions triggered_by: datetime, at: #{DateTime.to_unix(ref_time)} do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 10.0
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      next_tx = %Transaction{
        timestamp: ref_time,
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 10.0
                }
              ]
            }
          }
        }
      }

      assert true == Contracts.accept_new_contract?(previous_tx, next_tx)
    end

    test "should return false when the transaction have been triggered by interval but timestamp doesn't match " do
      code = """
      condition inherit: next_transaction.uco_transfers[\"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\"] == 10.0
      actions triggered_by: interval, at: "0 * * * * *" do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 10.0
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      {:ok, time} = DateTime.new(~D[2016-05-24], ~T[13:26:20], "Etc/UTC")

      next_tx = %Transaction{
        timestamp: time,
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 10.0
                }
              ]
            }
          }
        }
      }

      assert false == Contracts.accept_new_contract?(previous_tx, next_tx)
    end

    test "should return false when the transaction have been triggered by interval and the timestamp does match " do
      code = """
      condition inherit: next_transaction.uco_transfers[\"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\"] == 10.0
      actions triggered_by: interval, at: "0 * * * * *" do
        add_uco_transfer to: \"3265CCD78CD74984FAB3CC6984D30C8C82044EBBAB1A4FFFB683BDB2D8C5BCF9\", amount: 10.0
      end
      """

      previous_tx = %Transaction{
        data: %TransactionData{
          code: code
        }
      }

      {:ok, time} = DateTime.new(~D[2016-05-24], ~T[13:26:00.000999], "Etc/UTC")

      next_tx = %Transaction{
        timestamp: time,
        data: %TransactionData{
          code: code,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to:
                    <<50, 101, 204, 215, 140, 215, 73, 132, 250, 179, 204, 105, 132, 211, 12, 140,
                      130, 4, 78, 187, 171, 26, 79, 255, 182, 131, 189, 178, 216, 197, 188, 249>>,
                  amount: 10.0
                }
              ]
            }
          }
        }
      }

      assert true == Contracts.accept_new_contract?(previous_tx, next_tx)
    end
  end
end
