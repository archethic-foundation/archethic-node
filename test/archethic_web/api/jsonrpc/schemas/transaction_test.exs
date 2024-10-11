defmodule ArchethicWeb.API.JsonRPC.TransactionSchemaTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias ArchethicWeb.API.JsonRPC.TransactionSchema

  describe "validate/1" do
    test "should return :error if params are not a map" do
      assert :error = TransactionSchema.validate(["list"])
    end

    test "should return errors if there are missing fields in the transaction schema" do
      assert {:error,
              %{
                "#" =>
                  "Required properties version, address, type, previousPublicKey, previousSignature, originSignature, data were not present."
              }} = TransactionSchema.validate(%{})
    end

    test "should return errors if the crypto primitives are invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => "abc",
        "type" => "transfer",
        "data" => %{
          "code" => "",
          "content" => "hello",
          "ledger" => %{
            "uco" => %{
              "transfers" => []
            },
            "token" => %{
              "transfers" => []
            }
          },
          "ownerships" => [],
          "recipients" => []
        },
        "previousPublicKey" => "abc",
        "previousSignature" => "abc",
        "originSignature" => "abc"
      }

      assert {:error,
              %{
                "#/address" =>
                  "Expected exactly one of the schemata to match, but none of them did.",
                "#/originSignature" => "Does not match pattern \"^([0-9a-fA-F]{2})*$\".",
                "#/previousPublicKey" =>
                  "Expected exactly one of the schemata to match, but none of them did.",
                "#/previousSignature" => "Does not match pattern \"^([0-9a-fA-F]{2})*$\"."
              }} = TransactionSchema.validate(map)
    end

    test "should return error if there is additionnal properties" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{"unknownKey" => "hello"}
      }

      assert {
               :error,
               %{
                 "#/data/unknownKey" => "Schema does not allow additional properties.",
                 "#/timestamp" => "Schema does not allow additional properties."
               }
             } = TransactionSchema.validate(map)
    end

    test "should return an error if the content size is greater than content max size" do
      content = Base.encode16(:crypto.strong_rand_bytes(4 * 1024 * 1024))

      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{"content" => content}
      }

      assert {:error,
              %{
                "#/data/content" =>
                  "Expected value to have a maximum length of 3145728 but was 8388608."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the code is not a string" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{"code" => 123}
      }

      assert {:error, %{"#/data/code" => "Type mismatch. Expected String but got Integer."}} =
               TransactionSchema.validate(map)
    end

    test "should return an error if the code length is more than limit" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{"code" => generate_code_that_exceed_limit_when_compressed()}
      }

      assert {:error,
              %{
                "#/data/code" => "Invalid transaction, code exceed max size."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the uco ledger transfer address is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{"uco" => %{"transfers" => [%{"to" => "abc", "amount" => 10.0}]}}
        }
      }

      assert {:error,
              %{
                "#/data/ledger/uco/transfers/0/to" =>
                  "Expected exactly one of the schemata to match, but none of them did."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the uco ledger transfer amount is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "uco" => %{
              "transfers" => [
                %{
                  "to" => Base.encode16(random_address()),
                  "amount" => "abc"
                }
              ]
            }
          }
        }
      }

      assert {:error,
              %{
                "#/data/ledger/uco/transfers/0/amount" =>
                  "Type mismatch. Expected Integer but got String."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the uco ledger transfers are more than 255" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "uco" => %{
              "transfers" =>
                1..256
                |> Enum.map(fn _ ->
                  %{
                    "to" => Base.encode16(random_address()),
                    "amount" => Enum.random(1..100)
                  }
                end)
            }
          }
        }
      }

      assert {:error,
              %{"#/data/ledger/uco/transfers" => "Expected a maximum of 255 items but got 256."}} =
               TransactionSchema.validate(map)
    end

    test "should return an error if the token ledger transfer address is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "token" => %{
              "transfers" => [
                %{
                  "to" => "abc",
                  "amount" => 10.0,
                  "tokenAddress" => Base.encode16(random_address()),
                  "tokenId" => 0
                }
              ]
            }
          }
        }
      }

      assert {:error,
              %{
                "#/data/ledger/token/transfers/0/to" =>
                  "Expected exactly one of the schemata to match, but none of them did."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the token ledger transfer amount is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "token" => %{
              "transfers" => [
                %{
                  "to" => Base.encode16(random_address()),
                  "amount" => "abc",
                  "tokenAddress" => Base.encode16(random_address()),
                  "tokenId" => 0
                }
              ]
            }
          }
        }
      }

      assert {:error,
              %{
                "#/data/ledger/token/transfers/0/amount" =>
                  "Type mismatch. Expected Integer but got String."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the token ledger transfer token address is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "token" => %{
              "transfers" => [
                %{
                  "to" => Base.encode16(random_address()),
                  "amount" => 10.0,
                  "tokenAddress" => "abc",
                  "tokenId" => 0
                }
              ]
            }
          }
        }
      }

      assert {:error,
              %{
                "#/data/ledger/token/transfers/0/tokenAddress" =>
                  "Expected exactly one of the schemata to match, but none of them did."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the token ledger transfers are more than 255" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "token" => %{
              "transfers" =>
                1..256
                |> Enum.map(fn _ ->
                  %{
                    "to" => Base.encode16(random_address()),
                    "amount" => Enum.random(1..100),
                    "tokenAddress" => Base.encode16(random_address()),
                    "tokenId" => Enum.random(0..255)
                  }
                end)
            }
          }
        }
      }

      assert {:error,
              %{
                "#/data/ledger/token/transfers" => "Expected a maximum of 255 items but got 256."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the encrypted secret is not an hexadecimal" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ownerships" => [
            %{
              "secret" => "abc",
              "authorizedKeys" => [
                %{
                  "publicKey" => Base.encode16(random_address()),
                  "encryptedSecretKey" => "0123"
                }
              ]
            }
          ]
        }
      }

      assert {:error,
              %{
                "#/data/ownerships/0/secret" => "Does not match pattern \"^([0-9a-fA-F]{2})*$\"."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the public key in the authorized keys is not valid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ownerships" => [
            %{
              "authorizedKeys" => [
                %{
                  "publicKey" => "key",
                  "encryptedSecretKey" => "hello"
                }
              ]
            }
          ]
        }
      }

      assert {:error,
              %{
                "#/data/ownerships/0" => "Required property secret was not present.",
                "#/data/ownerships/0/authorizedKeys/0/encryptedSecretKey" =>
                  "Does not match pattern \"^([0-9a-fA-F]{2})*$\".",
                "#/data/ownerships/0/authorizedKeys/0/publicKey" =>
                  "Expected exactly one of the schemata to match, but none of them did."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error ownerships are more than 255." do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ownerships" =>
            1..256
            |> Enum.map(fn _ ->
              %{
                "secret" => Base.encode16(:crypto.strong_rand_bytes(64)),
                "authorizedKeys" => [
                  %{
                    "publicKey" =>
                      Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "encryptedSecretKey" => Base.encode16(:crypto.strong_rand_bytes(64))
                  }
                ]
              }
            end)
        }
      }

      assert {:error, %{"#/data/ownerships" => "Expected a maximum of 255 items but got 256."}} =
               TransactionSchema.validate(map)
    end

    test "should return an error authorized keys in a ownership can't be more than 255" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ownerships" => [
            %{
              "secret" => Base.encode16(:crypto.strong_rand_bytes(64)),
              "authorizedKeys" =>
                1..256
                |> Enum.map(fn _ ->
                  %{
                    "publicKey" => Base.encode16(random_address()),
                    "encryptedSecretKey" => Base.encode16(:crypto.strong_rand_bytes(64))
                  }
                end)
            }
          ]
        }
      }

      assert {:error,
              %{
                "#/data/ownerships/0/authorizedKeys" =>
                  "Expected a maximum of 255 items but got 256."
              }} = TransactionSchema.validate(map)
    end

    test "should return an error if the recipients are invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [1]
        }
      }

      assert {:error,
              %{
                "#/data/recipients/0" =>
                  "Expected exactly one of the schemata to match, but none of them did."
              }} = TransactionSchema.validate(map)

      map = put_in(map, ["data", "recipients"], [%{"address" => "hello"}])

      assert {:error,
              %{
                "#/data/recipients/0" =>
                  "Expected exactly one of the schemata to match, but none of them did."
              }} = TransactionSchema.validate(map)

      map =
        put_in(map, ["data", "recipients"], [
          %{
            "address" => Base.encode16(random_address()),
            "args" => []
          }
        ])

      assert {:error,
              %{
                "#/data/recipients/0" =>
                  "Expected exactly one of the schemata to match, but none of them did."
              }} = TransactionSchema.validate(map)
    end

    test "should accept recipients both named & unnamed" do
      map = %{
        "version" => 3,
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [
            %{
              "address" => Base.encode16(random_address())
            },
            %{
              "address" => Base.encode16(random_address()),
              "action" => "something",
              "args" => []
            }
          ]
        }
      }

      assert :ok = TransactionSchema.validate(map)

      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [
            %{
              "address" => Base.encode16(random_address())
            },
            %{
              "address" => Base.encode16(random_address()),
              "action" => "something",
              "args" => %{}
            }
          ]
        }
      }

      assert :ok = TransactionSchema.validate(map)
    end

    test "should return an error if the recipients are more that 255" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" =>
            1..256
            |> Enum.map(fn _ ->
              %{
                "address" => Base.encode16(random_address())
              }
            end)
        }
      }

      assert {:error, %{"#/data/recipients" => "Expected a maximum of 255 items but got 256."}} =
               TransactionSchema.validate(map)
    end

    test "should return error if transaction V1 contains named action recipient" do
      map = %{
        "version" => 1,
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [
            %{
              "address" => Base.encode16(random_address()),
              "action" => "something",
              "args" => []
            }
          ]
        }
      }

      assert {:error,
              %{"#/data/recipients" => "Transaction V1 cannot use named action recipients"}} =
               TransactionSchema.validate(map)
    end

    test "should return error if transaction V2 contains list of addresses as recipient" do
      map = %{
        "version" => 2,
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [Base.encode16(random_address())]
        }
      }

      assert {:error,
              %{"#/data/recipients" => "From V2, transaction must use named action recipients"}} =
               TransactionSchema.validate(map)
    end
  end

  describe "to_transaction/1" do
    test "should return a transaction struct" do
      address = random_address()
      previous_public_key = random_address()
      previous_signature = :crypto.strong_rand_bytes(64)
      origin_signature = :crypto.strong_rand_bytes(64)
      recipient = random_address()
      recipient2_address = random_address()
      uco_to = random_address()
      aes_key = :crypto.strong_rand_bytes(32)
      secret = Crypto.aes_encrypt("hello", aes_key)

      {authorized_public_key, _} = Crypto.generate_deterministic_keypair("seed")
      encrypted_key = Crypto.ec_encrypt(aes_key, authorized_public_key)

      transaction_version = current_transaction_version()

      map = %{
        "version" => transaction_version,
        "address" => Base.encode16(address),
        "type" => "transfer",
        "previousPublicKey" => Base.encode16(previous_public_key),
        "previousSignature" => Base.encode16(previous_signature),
        "originSignature" => Base.encode16(origin_signature),
        "data" => %{
          "contract" => %{
            "bytecode" => :crypto.strong_rand_bytes(32) |> Base.encode16(),
            "manifest" => %{
              "abi" => %{
                "state" => %{},
                "functions" => %{
                  "inc" => %{
                    "type" => "action",
                    "triggerType" => "transaction"
                  }
                }
              }
            }
          },
          "ledger" => %{
            "uco" => %{
              "transfers" => [
                %{"to" => Base.encode16(uco_to), "amount" => 1_020_000_000}
              ]
            }
          },
          "ownerships" => [
            %{
              "secret" => Base.encode16(secret),
              "authorizedKeys" => [
                %{
                  "publicKey" => Base.encode16(authorized_public_key),
                  "encryptedSecretKey" => Base.encode16(encrypted_key)
                }
              ]
            }
          ],
          "recipients" => [
            %{"address" => Base.encode16(recipient)},
            %{
              "address" => Base.encode16(recipient2_address),
              "action" => "something",
              "args" => [1, 2, 3]
            }
          ]
        }
      }

      :abi
      :functions

      assert %Transaction{
               version: ^transaction_version,
               address: ^address,
               type: :transfer,
               previous_public_key: ^previous_public_key,
               previous_signature: ^previous_signature,
               origin_signature: ^origin_signature,
               data: %TransactionData{
                 recipients: [
                   %Recipient{address: ^recipient, action: nil, args: nil},
                   %Recipient{
                     address: ^recipient2_address,
                     action: "something",
                     args: [1, 2, 3]
                   }
                 ],
                 ledger: %Ledger{
                   uco: %UCOLedger{
                     transfers: [
                       %UCOTransfer{to: ^uco_to, amount: 1_020_000_000}
                     ]
                   }
                 },
                 ownerships: [
                   %Ownership{
                     secret: ^secret,
                     authorized_keys: %{
                       ^authorized_public_key => ^encrypted_key
                     }
                   }
                 ],
                 contract: %{
                   bytecode: _,
                   manifest: %{
                     "abi" => %{
                       "functions" => %{
                         "inc" => %{
                           "type" => "action",
                           "triggerType" => "transaction"
                         }
                       },
                       "state" => %{}
                     }
                   }
                 }
               }
             } = TransactionSchema.to_transaction(map)
    end
  end
end
