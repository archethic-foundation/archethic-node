defmodule ArchethicWeb.AEWeb.DomainTest do
  alias Archethic.TransactionFactory
  alias ArchethicWeb.AEWeb.Domain

  alias Archethic.Crypto

  alias Archethic.P2P.Node

  alias Archethic.P2P

  alias Archethic.P2P.Message.GetLastTransactionAddress

  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.GetTransaction

  alias Archethic.TransactionChain.TransactionData.Ownership

  use ArchethicCase

  import ArchethicCase

  import Mox

  describe "lookup_dnslink_address/1" do
    test "should return correct dnslink address when present" do
      MockDNSClient
      |> expect(:lookup, fn '_dnslink.example.com', :in, :txt, _options ->
        [['dnslink=/archethic/some_tx_address']]
      end)

      assert {:ok, "some_tx_address"} =
               ArchethicWeb.AEWeb.Domain.lookup_dnslink_address("example.com")
    end

    test "should return :not_found when no dnslink is present" do
      MockDNSClient
      |> expect(:lookup, fn '_dnslink.not_found.com', :in, :txt, _options -> [] end)

      assert {:error, :not_found} =
               ArchethicWeb.AEWeb.Domain.lookup_dnslink_address("not_found.com")
    end

    test "should return :not_found when dnslink has invalid format" do
      MockDNSClient
      |> expect(:lookup, fn '_dnslink.invalid.com', :in, :txt, _options ->
        [['invalid_record']]
      end)

      assert {:error, :not_found} =
               ArchethicWeb.AEWeb.Domain.lookup_dnslink_address("invalid.com")
    end
  end

  describe "sni/1" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {122, 12, 0, 5},
        port: 3000,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      genesis_address = random_address()

      MockDNSClient
      |> stub(:lookup, fn
        _, :in, :txt, _options ->
          [["dnslink=/archethic/#{Base.encode16(genesis_address)}"]]
      end)

      fake_cert_pem = """
      -----BEGIN CERTIFICATE-----
      MIIDQTCCAimgAwIBAgIUc6RgG5TIwlnglJma6l1pi1IojXcwDQYJKoZIhvcNAQEL
      BQAwFjEUMBIGA1UEAwwLZXhhbXBsZS5jb20wHhcNMjQxMDIzMDg0NDA5WhcNMjUx
      MDIzMDg0NDA5WjAWMRQwEgYDVQQDDAtleGFtcGxlLmNvbTCCASIwDQYJKoZIhvcN
      AQEBBQADggEPADCCAQoCggEBAPQ1StLICyM65hHtBhQmhMIyI4TtKPeGNQeAyexF
      Km9F4uJkB2tMDSr1Wgcnc9+GYWiijRjey0HjVHhkVi0GbTiK8z25N3bd6UXuJdNC
      yvZ7jBBRgUsiIXnr/jjGhciRTG5IWrXmtG0zE3rgnqLRcbyy26WnlelcgoFjuW1B
      mlN+8IicWbXO1pUOkBpePQJnin0Yv67aF6hSbyJkLSqjqlK3TVt9to6ksq3wRG5q
      5dODqKJXi3lcuNMfkBmuygHbMqtvsu+cIl73h8LVhKWtpoPXC4ShS7nol61uZSzI
      Te5gp82VKfBZEn0LnMrPvnBDxVGq2MPOA+jBnQtzPE4+8/8CAwEAAaOBhjCBgzBi
      BgNVHREEWzBZggtleGFtcGxlLmNvbYIQYmxvZy5leGFtcGxlLmNvbYISKi53aWtp
      LmV4YW1wbGUuY29tghVkYXNoYm9hcmQuZXhhbXBsZS5jb22CDSouZXhhbXBsZS5j
      b20wHQYDVR0OBBYEFLULaIwvOBD0pxgQfZjzHDdWGGFsMA0GCSqGSIb3DQEBCwUA
      A4IBAQAYp7hQGOKMwY9YGrR2gylXDPMhcmCLS8O2gLV1Uhr5tutBheKA0/S+/HAp
      5gMXwwxVpxknDskZAbI6675OeSJ03eRmYuhYNJIILsuY0ZFfr4oVuI+WMXegdmaf
      g3zT/WbZeaNjNzZ0sZbe+/D+ZWJrDk6xEsndup1604hQ59hQxKgZWmlDDeWSLQj7
      QeWQSchpB4+mknP3XeTTRFT3bO00mcTfa+Y20FIGBnYzD7hsul9I6coqx0GpRXwJ
      J6+1a2APHvLjmNUBlO+va7EzESjpBO7s6/CzC6EUeOaqxeKBec5tnNB6Lmy1TfbG
      yds+RPeP9zA9f5EA/Gk/ap4aXht5
      -----END CERTIFICATE-----
      """

      fake_key_pem = """
      -----BEGIN PRIVATE KEY-----
      MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQD0NUrSyAsjOuYR
      7QYUJoTCMiOE7Sj3hjUHgMnsRSpvReLiZAdrTA0q9VoHJ3PfhmFooo0Y3stB41R4
      ZFYtBm04ivM9uTd23elF7iXTQsr2e4wQUYFLIiF56/44xoXIkUxuSFq15rRtMxN6
      4J6i0XG8stulp5XpXIKBY7ltQZpTfvCInFm1ztaVDpAaXj0CZ4p9GL+u2heoUm8i
      ZC0qo6pSt01bfbaOpLKt8ERuauXTg6iiV4t5XLjTH5AZrsoB2zKrb7LvnCJe94fC
      1YSlraaD1wuEoUu56JetbmUsyE3uYKfNlSnwWRJ9C5zKz75wQ8VRqtjDzgPowZ0L
      czxOPvP/AgMBAAECgf9L1kDmNDlBN4k7B+BbYZrYs7lUDlIqjALr0ZLjTJdg9tL+
      exHSwEtWi9rpXdceEx0s4U3v60AzteUFfiNE2DoS1RO0l1AiGcfXb51Pfe6JnNRi
      PO1p5699rUvFVeE15+lUViPVWU+uma3y+s5IwcIQV3redqyXS6M7izyKMVU7mBTK
      e63pDSu2cxODfE9p3M/Mvk1uaf+OQ4qBDqsh45q6QDZWMuVw+iitt+vMub8a2EzS
      HryRSGcfg9zgvcOcOKjp1u/UjAsO2tCfXMZLQoWEG8RmFOnPqVlh2ZXfmCvtCP1W
      K2fUuOmc0ddFBhO3vk5gqO5Jsh+CVj6sjTZlaRkCgYEA/cQBbhoYO4D+diDr3D5N
      01Z+kZ4HmgrW6gahef+MNy9YWXooghlcKe7IYXlBqsMI/IiyK9zbMAcOK61zi/Le
      EezoXbjdk+6VvuniPJEWX/JquJoqiTmDwzP0lQEM/aKdOG624zYfObjJ6aBaf/xk
      ssdHRhOfGp9pFSaHA0KO3PcCgYEA9lu+b/n2v0JeEG7IR1RzJ1Ud4DhgZyvvIggf
      hxX5tMZ0E8ywOnJ4g2o3qowI4XJmDCudI29cmTNgVKqwUduDgOoAkdlpoWvhY3yb
      DzmC8Fim+/MAOGGPyRAuPovBm+dGH0fQnatS0tuo5MpKRB2BnJ3RrJ4Qm1f3G/we
      gA6DBzkCgYB+9VUR1JRTENI+H3JhGfqtxRRFnh6HfuzO4Mpg0u0/nrxA59DkZfOq
      NwChY5zq5fDVBz68mx4+BQmd6IVqevOHXFNUsGyK2k6o2TKKwrvC/PFPsjGdvdyi
      CJhRA9mP+49U8G8ndahhpIXAEK22Ynuuxexurtpm42IbZs8dXmtDOQKBgQC9fbnQ
      VXsWh8zkZOHGA84DHfQ56AM2uFNaYNcnR57nDpJwPEv82Nmbc1LX6phWGHEnwVA/
      1kNqT1s0JIo0nFzdBqBjjtAx6lHV/R0jq7/scLQYLUQpGdnH9JstXsAP0+da3hk3
      fXTaXTzepj5TgEKWncmONZJeel3G97jaFM9x+QKBgQCWW3sPWKh/9Z5LSn48irDF
      88dy1WqPPZXllilNNvrTA7bMfXQqN14doFTMcWaAUoEDl7H/sWSuBFFQddYKsLSR
      SC9ttOp9kKUYgCxGmbE3Fwj8LsuyddhGisZ0edC2rJvVvCQMCIgUS9VvSnpzpiay
      rgoVgtbapk/vMon8gnjqMw==
      -----END PRIVATE KEY-----

      """

      https_conf =
        :archethic
        |> Application.get_env(ArchethicWeb.Endpoint)
        |> Keyword.fetch!(:https)

      keyfile = Keyword.fetch!(https_conf, :keyfile)
      certfile = Keyword.fetch!(https_conf, :certfile)

      unlisted_domain_key_pem = File.read!(Application.app_dir(:archethic, keyfile))

      unlisted_domain_cert_pem = File.read!(Application.app_dir(:archethic, certfile))

      %{
        fake_cert_pem: fake_cert_pem,
        genesis_address: genesis_address,
        fake_key_pem: fake_key_pem,
        unlisted_domain_cert_pem: unlisted_domain_cert_pem,
        unlisted_domain_key_pem: unlisted_domain_key_pem
      }
    end

    test "should return the correct key and cert for a domain", %{
      fake_cert_pem: fake_cert_pem,
      genesis_address: genesis_address,
      fake_key_pem: fake_key_pem
    } do
      setup_transaction(fake_key_pem, fake_cert_pem, genesis_address)

      result = Domain.sni("example.com")

      expected_key = read_pem(fake_key_pem) |> hd()
      expected_cert = read_pem(fake_cert_pem) |> hd() |> elem(1)
      assert [key: expected_key, cert: expected_cert] == result

      result = Domain.sni("blog.example.com")

      assert [key: expected_key, cert: expected_cert] == result

      result = Domain.sni("some-other-pages.example.com")

      assert [key: expected_key, cert: expected_cert] == result
    end

    test "should return the fallback key and cert for an unlisted domain", %{
      fake_cert_pem: fake_cert_pem,
      genesis_address: genesis_address,
      fake_key_pem: fake_key_pem,
      unlisted_domain_cert_pem: unlisted_domain_cert_pem,
      unlisted_domain_key_pem: unlisted_domain_key_pem
    } do
      setup_transaction(fake_key_pem, fake_cert_pem, genesis_address)
      result_listed_domain = Domain.sni("example.com")

      result_unlisted_domain = Domain.sni("toto.com")
      expected_key = read_pem(unlisted_domain_key_pem) |> hd()
      expected_cert = read_pem(unlisted_domain_cert_pem) |> hd() |> elem(1)

      assert [key: expected_key, cert: expected_cert] == result_unlisted_domain

      refute result_listed_domain == result_unlisted_domain
    end
  end

  defp setup_transaction(fake_key_pem, fake_cert_pem, genesis_address) do
    aes_key = :crypto.strong_rand_bytes(32)

    secret = Crypto.aes_encrypt(fake_key_pem, aes_key)

    authorized_key = Crypto.storage_nonce_public_key()

    ownership = Ownership.new(secret, aes_key, [authorized_key])

    content = Jason.encode!(%{"sslCertificate" => fake_cert_pem})

    tx =
      TransactionFactory.create_valid_transaction(
        [],
        content: content,
        ownerships: [ownership],
        type: :hosting
      )

    tx_address = tx.address

    MockClient
    |> stub(
      :send_message,
      fn
        _, %GetLastTransactionAddress{address: ^genesis_address}, _ ->
          {:ok, %LastTransactionAddress{address: tx.address}}

        _, %GetTransaction{address: ^tx_address}, _ ->
          {:ok, tx}
      end
    )
  end

  defp read_pem(pem_string) do
    pem_string
    |> :public_key.pem_decode()
    |> Enum.map(fn entry ->
      entry = :public_key.pem_entry_decode(entry)
      type = elem(entry, 0)
      {type, :public_key.der_encode(type, entry)}
    end)
  end
end
