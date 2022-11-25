defmodule ArchethicWeb.API.WebHosting.CheckSumTest do
  @moduledoc false
  use ExUnit.Case
  alias ArchethicWeb.API.WebHosting.CheckSum
  doctest CheckSum

  describe "checksum" do
    test "fetch_txn" do
      %{
        "00003bdda8b4a56f588dafe0d14b6ee59592cec7cfbc4e106e1a45b536b05b6b07b6" => nil,
        "00004057e7a8da1d504bca6d06fabd0bafbe40c77c81baacbff04036147c02c46018" => nil,
        "00004e4a8561c74f02be2e13995a96bcc4071dbcfee3480beb5e264b1326e0be5c5f" => nil,
        "0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6" => nil,
        "00006766f61e804c98261b27a63ee48089ded4fe53b792deeacd4d69097e2d43eff2" => nil,
        "00009c92dce5faf3c6d27b5ff9330be0e8399d55063199caaaa17905cb87e65e1dbb" => nil,
        "0000b6e22bdaca1d01f503d07f7d53dd2792ce1e095765b31138a8827601986e696c" => nil,
        "0000b93e54594cc8e606e14342457503d95c20106eeebc9514d0aded9f638af4c1d7" => nil,
        "0000c39b14f4dc86f66d0e20963fa4f1149ce767884ec2fa9a183f94572f43902a89" => nil
      }
      |> CheckSum.fetch_txn()
    end

    def txn_to_content() do
      %{
        "00003bdda8b4a56f588dafe0d14b6ee59592cec7cfbc4e106e1a45b536b05b6b07b6" => %{
          "ARCHEthic_WhitePaper.pdf" => "CSu4GUS6ual"
        },
        "00004057e7a8da1d504bca6d06fabd0bafbe40c77c81baacbff04036147c02c46018" => %{
          "ARCHEthic_YellowPaper.pdf" => "SmUUicSdP3"
        },
        "00004e4a8561c74f02be2e13995a96bcc4071dbcfee3480beb5e264b1326e0be5c5f" => %{
          "ARCHEthic_WhitePaper.pdf" => "zQfVkloDo1"
        },
        "0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6" => %{
          "ARCHEthic_UCOnomics.pdf" => "H4sIAAAAAAAAA",
          "README.md" => "E4qjfo9r77DcvpKc7JAwAA",
          "assets" => %{
            "README.md" => "H4sIAAAAAAAAA1NWc",
            "community1" => %{"may-2022.png" => "H4sIAA", "uniswap.png" => "620twgAAA"},
            "partners" => %{
              "build" => %{"bundle.css" => "H4sIIf9QPUPw", "bundle.js" => "H4sIA7y9"},
              "march-2022.png" => "dJJWfAEELUDS5E6BKdOalqVwT",
              "uniswap.png" => "otTe8BAb8BAU0kRYggYvUBFKSlFHpJ8",
              "zam-2.png" => "kcQX7jOUBnNsztb8t3n"
            },
            "section-icons" => %{
              "white_logos" => %{
                "tla+.svg" => "MVAS1HD9YVrr4Wm"
              }
            }
          },
          "build" => %{
            "bundle.css" => "H4sIAAAAAAAAA-T7V4_sTJfvilvu7uf_6rvnf1v_7bX1Xrdnf5P4dx6ePu75ozr",
            "sitemap.xml" => "H4sIAAAAAAAAA5XQsQ7"
          },
          "sitemap.xml" => "H4sIAAAAAAAAA5XQsQ7CIBCA4d3E"
        },
        "00009c92dce5faf3c6d27b5ff9330be0e8399d55063199caaaa17905cb87e65e1dbb" => %{
          "ARCHEthic_WhitePaper.pdf" => "gcdUi-78989890"
        },
        "0000b93e54594cc8e606e14342457503d95c20106eeebc9514d0aded9f638af4c1d7" => %{
          "ARCHEthic_YellowPaper.pdf" => "H4sIAAAAAAAA"
        }
      }
    end

    test " txn to fetch" do
      assert get_json()
             |> CheckSum.file_to_address()
             |> elem(1)
             |> CheckSum.txn_to_fetch() ===
               %{
                 "00003bdda8b4a56f588dafe0d14b6ee59592cec7cfbc4e106e1a45b536b05b6b07b6" => nil,
                 "00004057e7a8da1d504bca6d06fabd0bafbe40c77c81baacbff04036147c02c46018" => nil,
                 "00004e4a8561c74f02be2e13995a96bcc4071dbcfee3480beb5e264b1326e0be5c5f" => nil,
                 "0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6" => nil,
                 "00006766f61e804c98261b27a63ee48089ded4fe53b792deeacd4d69097e2d43eff2" => nil,
                 "00009c92dce5faf3c6d27b5ff9330be0e8399d55063199caaaa17905cb87e65e1dbb" => nil,
                 "0000b6e22bdaca1d01f503d07f7d53dd2792ce1e095765b31138a8827601986e696c" => nil,
                 "0000b93e54594cc8e606e14342457503d95c20106eeebc9514d0aded9f638af4c1d7" => nil,
                 "0000c39b14f4dc86f66d0e20963fa4f1149ce767884ec2fa9a183f94572f43902a89" => nil
               }
    end

    test "|> CheckSum.file_to_address" do
      assert get_json()
             |> CheckSum.file_to_address()
             |> elem(1) ==
               [
                 {"ARCHEthic_UCOnomics.pdf",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"ARCHEthic_WhitePaper.pdf",
                  [
                    "00004e4a8561c74f02be2e13995a96bcc4071dbcfee3480beb5e264b1326e0be5c5f",
                    "00003bdda8b4a56f588dafe0d14b6ee59592cec7cfbc4e106e1a45b536b05b6b07b6",
                    "00009c92dce5faf3c6d27b5ff9330be0e8399d55063199caaaa17905cb87e65e1dbb"
                  ]},
                 {"ARCHEthic_YellowPaper.pdf",
                  [
                    "0000b93e54594cc8e606e14342457503d95c20106eeebc9514d0aded9f638af4c1d7",
                    "00004057e7a8da1d504bca6d06fabd0bafbe40c77c81baacbff04036147c02c46018"
                  ]},
                 {"README.md",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/README.md",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/community1/may-2022.png",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/community1/uniswap.png",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/partners/build/bundle.css",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/partners/build/bundle.js",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/partners/march-2022.png",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/partners/uniswap.png",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/partners/zam-2.png",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"assets/section-icons/beigner.pdf",
                  [
                    "0000c39b14f4dc86f66d0e20963fa4f1149ce767884ec2fa9a183f94572f43902a89",
                    "00006766f61e804c98261b27a63ee48089ded4fe53b792deeacd4d69097e2d43eff2",
                    "0000b6e22bdaca1d01f503d07f7d53dd2792ce1e095765b31138a8827601986e696c"
                  ]},
                 {"assets/section-icons/white_logos/tla+.svg",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"build/bundle.css",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"build/sitemap.xml",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]},
                 {"sitemap.xml",
                  ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"]}
               ]
    end
  end

  def get_json() do
    %{
      "ARCHEthic_UCOnomics.pdf" => %{
        "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
        "encodage" => "gzip"
      },
      "ARCHEthic_WhitePaper.pdf" => %{
        "address" => [
          "00004e4a8561c74f02be2e13995a96bcc4071dbcfee3480beb5e264b1326e0be5c5f",
          "00003bdda8b4a56f588dafe0d14b6ee59592cec7cfbc4e106e1a45b536b05b6b07b6",
          "00009c92dce5faf3c6d27b5ff9330be0e8399d55063199caaaa17905cb87e65e1dbb"
        ],
        "encodage" => "gzip"
      },
      "ARCHEthic_YellowPaper.pdf" => %{
        "address" => [
          "0000b93e54594cc8e606e14342457503d95c20106eeebc9514d0aded9f638af4c1d7",
          "00004057e7a8da1d504bca6d06fabd0bafbe40c77c81baacbff04036147c02c46018"
        ],
        "encodage" => "gzip"
      },
      "README.md" => %{
        "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
        "encodage" => "gzip"
      },
      "assets" => %{
        "README.md" => %{
          "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
          "encodage" => "gzip"
        },
        "community1" => %{
          "may-2022.png" => %{
            "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
            "encodage" => "gzip"
          },
          "uniswap.png" => %{
            "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
            "encodage" => "gzip"
          }
        },
        "partners" => %{
          "build" => %{
            "bundle.css" => %{
              "address" => [
                "0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"
              ],
              "encodage" => "gzip"
            },
            "bundle.js" => %{
              "address" => [
                "0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"
              ],
              "encodage" => "gzip"
            }
          },
          "march-2022.png" => %{
            "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
            "encodage" => "gzip"
          },
          "uniswap.png" => %{
            "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
            "encodage" => "gzip"
          },
          "zam-2.png" => %{
            "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
            "encodage" => "gzip"
          }
        },
        "section-icons" => %{
          "beigner.pdf" => %{
            "address" => [
              "0000c39b14f4dc86f66d0e20963fa4f1149ce767884ec2fa9a183f94572f43902a89",
              "00006766f61e804c98261b27a63ee48089ded4fe53b792deeacd4d69097e2d43eff2",
              "0000b6e22bdaca1d01f503d07f7d53dd2792ce1e095765b31138a8827601986e696c"
            ],
            "encodage" => "gzip"
          },
          "white_logos" => %{
            "tla+.svg" => %{
              "address" => [
                "0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"
              ],
              "encodage" => "gzip"
            }
          }
        }
      },
      "build" => %{
        "bundle.css" => %{
          "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
          "encodage" => "gzip"
        },
        "sitemap.xml" => %{
          "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
          "encodage" => "gzip"
        }
      },
      "sitemap.xml" => %{
        "address" => ["0000565da0bcfd309a432d0764392b67d2a4e1d773d36c46586f4948ea291ad8c7a6"],
        "encodage" => "gzip"
      }
    }
  end
end
