defmodule ArchethicWeb.API.TransactionPayloadTest do
  use ExUnit.Case

  alias Archethic.Crypto

  alias ArchethicWeb.API.TransactionPayload

  alias Ecto.Changeset

  describe "changeset/1" do
    test "should return errors if params is not a map" do
      assert :error = TransactionPayload.changeset(nil)
      assert :error = TransactionPayload.changeset(1)
      assert :error = TransactionPayload.changeset("1")
    end

    test "should return errors if there are missing fields in the transaction schema" do
      assert {:ok,
              %Ecto.Changeset{
                valid?: false,
                errors: [
                  data: {"can't be blank", [validation: :required]},
                  version: {"can't be blank", [validation: :required]},
                  address: {"can't be blank", [validation: :required]},
                  type: {"can't be blank", [validation: :required]},
                  previousPublicKey: {"can't be blank", [validation: :required]},
                  previousSignature: {"can't be blank", [validation: :required]},
                  originSignature: {"can't be blank", [validation: :required]}
                ]
              }} = TransactionPayload.changeset(%{})
    end

    test "should return errors if the crypto primitives are invalid" do
      assert {:ok,
              %Ecto.Changeset{
                valid?: false,
                errors: [
                  address: {"must be hexadecimal", _},
                  previousPublicKey: {"must be hexadecimal", _},
                  previousSignature: {"must be hexadecimal", _},
                  originSignature: {"must be hexadecimal", _}
                ]
              }} =
               TransactionPayload.changeset(%{
                 "version" => 1,
                 "address" => "abc",
                 "type" => "transfer",
                 "data" => %{
                   "code" => "",
                   "content" => "",
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
               })
    end

    test "should return an error if the content is not in hex" do
      {:ok,
       %Ecto.Changeset{
         valid?: false,
         changes: %{data: %{errors: errors}}
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{"content" => "hello"}
        })

      assert {"must be hexadecimal", _} = Keyword.get(errors, :content)
    end

    test "should return an error if the content size is greater than content max size" do
      content = Base.encode16(:crypto.strong_rand_bytes(4 * 1024 * 1024))

      {:ok,
       %Ecto.Changeset{
         valid?: false,
         changes: %{data: %{errors: errors}}
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{"content" => content}
        })

      assert {"content size must be less than content_max_size", _} =
               Keyword.get(errors, :content)
    end

    test "should return an error if the code is not a string" do
      {:ok,
       %Ecto.Changeset{
         valid?: false,
         changes: %{data: %{errors: errors}}
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{"code" => 123}
        })

      assert {"is invalid", _} = Keyword.get(errors, :code)
    end

    test "should return an error if the code length is more than 24KB" do
      {:ok,
       %Ecto.Changeset{
         valid?: false,
         changes: %{data: %{errors: errors}}
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{"code" => Base.encode16(:crypto.strong_rand_bytes(24 * 1024 + 1))}
        })

      {error_message, _} = Keyword.get(errors, :code)
      assert String.starts_with?(error_message, "code size can't be more than ")
    end

    test "should return an error if the uco ledger transfer address is invalid" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{"uco" => %{"transfers" => [%{"to" => "abc", "amount" => 10.0}]}}
          }
        })

      assert [%{to: ["must be hexadecimal"]}] =
               changeset
               |> get_errors()
               |> get_in([:data, :ledger, :uco, :transfers])
    end

    test "should return an error if the uco ledger transfer amount is invalid" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "uco" => %{
                "transfers" => [
                  %{
                    "to" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => "abc"
                  }
                ]
              }
            }
          }
        })

      assert [%{amount: ["is invalid"]}] =
               changeset |> get_errors() |> get_in([:data, :ledger, :uco, :transfers])
    end

    test "should return an error if the uco ledger transfers are more than 256" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "uco" => %{
                "transfers" =>
                  1..257
                  |> Enum.map(fn _ ->
                    %{
                      "to" =>
                        Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                      "amount" => Enum.random(1..100)
                    }
                  end)
              }
            }
          }
        })

      assert %{transfers: ["maximum uco transfers in a transaction can be 256"]} =
               changeset |> get_errors() |> get_in([:data, :ledger, :uco])
    end

    test "should return an error if the token ledger transfer address is invalid" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "token" => %{
                "transfers" => [
                  %{
                    "to" => "abc",
                    "amount" => 10.0,
                    "token" =>
                      Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "tokenId" => 0
                  }
                ]
              }
            }
          }
        })

      assert [%{to: ["must be hexadecimal"]}] =
               changeset |> get_errors() |> get_in([:data, :ledger, :token, :transfers])
    end

    test "should return an error if the token ledger transfer amount is invalid" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "token" => %{
                "transfers" => [
                  %{
                    "to" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => "abc",
                    "token" =>
                      Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "tokenId" => 0
                  }
                ]
              }
            }
          }
        })

      assert [
               %{
                 amount: [
                   "is invalid"
                 ]
               }
             ] = changeset |> get_errors |> get_in([:data, :ledger, :token, :transfers])
    end

    test "should return an error if the token ledger transfer token address is invalid" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "token" => %{
                "transfers" => [
                  %{
                    "to" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => 10.0,
                    "tokenAddress" => "abc",
                    "tokenId" => 0
                  }
                ]
              }
            }
          }
        })

      assert [%{tokenAddress: ["must be hexadecimal"]}] =
               changeset |> get_errors |> get_in([:data, :ledger, :token, :transfers])
    end

    test "should return an error if the token ledger transfers are more than 256" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "token" => %{
                "transfers" =>
                  1..257
                  |> Enum.map(fn _ ->
                    %{
                      "to" =>
                        Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                      "amount" => Enum.random(1..100),
                      "tokenAddress" =>
                        Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                      "tokenId" => Enum.random(0..255)
                    }
                  end)
              }
            }
          }
        })

      assert %{transfers: ["maximum token transfers in a transaction can be 256"]} =
               changeset |> get_errors |> get_in([:data, :ledger, :token])
    end

    test "should return an error if the encrypted secret is not an hexadecimal" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" => [
              %{"secret" => "abc"}
            ]
          }
        })

      assert [%{secret: ["must be hexadecimal"]}] =
               changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the public key in the authorized keys is not valid" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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
        })

      assert [
               %{
                 authorizedKeys: [
                   %{
                     publicKey: ["must be hexadecimal"],
                     encryptedSecretKey: ["must be hexadecimal"]
                   }
                 ]
               }
             ] = changeset |> get_errors |> get_in([:data, :ownerships])

      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" => [
              %{
                "authorizedKeys" => [
                  %{
                    "publicKey" => Base.encode16(:crypto.strong_rand_bytes(32)),
                    "encryptedSecretKey" => "hello"
                  }
                ]
              }
            ]
          }
        })

      assert [
               %{
                 authorizedKeys: [
                   %{publicKey: ["invalid key size"], encryptedSecretKey: ["must be hexadecimal"]}
                 ]
               }
             ] = changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the encrypted key in the authorized keys is not valid" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" => [
              %{
                "authorizedKeys" => [
                  %{
                    "publicKey" =>
                      Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "encryptedSecretKey" => "hello"
                  }
                ]
              }
            ]
          }
        })

      assert [%{authorizedKeys: [%{encryptedSecretKey: ["must be hexadecimal"]}]}] =
               changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error ownerships are more than 255." do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" =>
              1..256
              |> Enum.map(fn _ ->
                %{
                  "authorizedKeys" =>
                    Enum.map(1..2, fn _ ->
                      %{
                        "publicKey" =>
                          Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                        "encryptedSecretKey" => Base.encode16(:crypto.strong_rand_bytes(45))
                      }
                    end),
                  "secret" => Base.encode16(<<:crypto.strong_rand_bytes(64)::binary>>)
                }
              end)
          }
        })

      {msg, _} = changeset.errors[:ownerships]
      assert "ownerships can not be more that 255" == msg
    end

    test "should return an error authorized keys in a ownership can't be more than 255" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" => [
              %{
                "authorizedKeys" =>
                  1..257
                  |> Enum.map(fn _ ->
                    %{
                      "publicKey" =>
                        Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                      "encryptedSecretKey" => Base.encode16(:crypto.strong_rand_bytes(64))
                    }
                  end),
                "secret" => Base.encode16(:crypto.strong_rand_bytes(64))
              }
            ]
          }
        })

      assert [%{authorizedKeys: ["maximum number of authorized keys can be 255"]}] =
               changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the recipients are invalid" do
      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 2,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "recipients" => [1]
          }
        })

      assert ["invalid recipient format"] =
               changeset |> get_errors() |> get_in([:data, :recipients])

      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 2,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "recipients" => [
              %{"address" => "hello"}
            ]
          }
        })

      assert ["must be hexadecimal"] = changeset |> get_errors() |> get_in([:data, :recipients])

      {:ok,
       changeset = %Ecto.Changeset{
         valid?: false
       }} =
        TransactionPayload.changeset(%{
          "version" => 2,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "recipients" => [%{"address" => Base.encode16(:crypto.strong_rand_bytes(32))}]
          }
        })

      assert ["invalid hash"] = changeset |> get_errors() |> get_in([:data, :recipients])

      {:ok, changeset} =
        {:ok,
         %Ecto.Changeset{
           valid?: false
         }} =
        TransactionPayload.changeset(%{
          "version" => 2,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "recipients" => [
              %{
                "address" => "not an hexadecimal",
                "action" => "upgrade",
                "args" => []
              }
            ]
          }
        })

      assert ["must be hexadecimal"] = changeset |> get_errors() |> get_in([:data, :recipients])

      {:ok, changeset} =
        {:ok,
         %Ecto.Changeset{
           valid?: false
         }} =
        TransactionPayload.changeset(%{
          "version" => 2,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "recipients" => [
              %{
                "address" => "not an hexadecimal",
                "args" => []
              }
            ]
          }
        })

      assert ["invalid recipient format"] =
               changeset |> get_errors() |> get_in([:data, :recipients])
    end

    test "should accept recipients both named & unnamed" do
      assert {:ok, %Ecto.Changeset{valid?: true}} =
               TransactionPayload.changeset(%{
                 "version" => 1,
                 "address" =>
                   Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                 "type" => "transfer",
                 "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
                 "previousPublicKey" =>
                   Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                 "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
                 "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
                 "data" => %{
                   "recipients" => [
                     %{
                       "address" =>
                         Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>)
                     },
                     %{
                       "address" =>
                         Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                       "action" => "something",
                       "args" => []
                     }
                   ]
                 }
               })
    end

    test "should return an error if the recipients are more that 255" do
      {:ok, changeset} =
        {:ok,
         %Ecto.Changeset{
           valid?: false
         }} =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "recipients" =>
              1..256
              |> Enum.map(fn _ ->
                %{
                  "address" =>
                    Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>)
                }
              end)
          }
        })

      assert ["maximum number of recipients can be 255"] =
               changeset |> get_errors() |> get_in([:data, :recipients])
    end
  end

  test "to_map/1 should return a map of the changeset" do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    previous_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    previous_signature = :crypto.strong_rand_bytes(64)
    origin_signature = :crypto.strong_rand_bytes(64)
    recipient = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    recipient2_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    uco_to = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    aes_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("hello", aes_key)

    {authorized_public_key, _} = Crypto.generate_deterministic_keypair("seed")
    encrypted_key = Crypto.ec_encrypt(aes_key, authorized_public_key)

    assert %{
             version: 1,
             address: address,
             type: "transfer",
             previous_public_key: previous_public_key,
             previous_signature: previous_signature,
             origin_signature: origin_signature,
             data: %{
               recipients: [
                 %{address: recipient, action: nil, args: nil},
                 %{
                   address: recipient2_address,
                   action: "something",
                   args: [1, 2, 3]
                 }
               ],
               ledger: %{
                 uco: %{
                   transfers: [
                     %{to: uco_to, amount: 1_020_000_000}
                   ]
                 }
               },
               ownerships: [
                 %{
                   secret: secret,
                   authorized_keys: %{
                     authorized_public_key => encrypted_key
                   }
                 }
               ]
             }
           } ==
             TransactionPayload.changeset(%{
               "version" => 1,
               "address" => Base.encode16(address),
               "type" => "transfer",
               "previousPublicKey" => Base.encode16(previous_public_key),
               "previousSignature" => Base.encode16(previous_signature),
               "originSignature" => Base.encode16(origin_signature),
               "data" => %{
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
             })
             |> elem(1)
             |> TransactionPayload.to_map()
  end

  defp get_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {msg, _} ->
      msg
    end)
  end
end
