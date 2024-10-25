defmodule ArchethicWeb.AEWeb.Domain do
  @moduledoc """
  Manage AEWeb domain logic
  """

  alias Archethic
  alias Archethic.Crypto
  alias Archethic.TransactionChain.TransactionData.Ownership

  alias ArchethicWeb.AEWeb.WebHostingController.ReferenceTransaction

  alias ArchethicWeb.AEWeb.DNSClient

  require Logger

  @doc """
  Lookup dns link address from host
  """
  @spec lookup_dnslink_address(binary()) :: {:ok, binary()} | {:error, :not_found}
  def lookup_dnslink_address(host) do
    dns_name =
      host
      |> to_string()
      |> String.split(":")
      |> List.first()

    case DNSClient.lookup('_dnslink.#{dns_name}', :in, :txt,
           # Allow local dns to test dnslink redirection
           alt_nameservers: [{{127, 0, 0, 1}, 53}]
         ) do
      [] ->
        {:error, :not_found}

      [[dnslink_entry]] ->
        case Regex.scan(~r/(?<=dnslink=\/archethic\/).*/, to_string(dnslink_entry)) do
          [] ->
            {:error, :not_found}

          [match] ->
            {:ok, List.first(match)}
        end
    end
  end

  @doc """
  Allows to change the SSL options during the TCP handshake.

  This make possible to load dynamically the SSL certificates and delivery multiple secure websites over HTTPS
  """
  def sni(domain) do
    domain = to_string(domain)

    with {:ok, tx_address} <- lookup_dnslink_address(domain),
         {:ok, tx_address} <- Base.decode16(tx_address, case: :mixed),
         {:ok,
          %ReferenceTransaction{
            json_content: json_content,
            ownerships: [ownership = %Ownership{secret: secret} | _]
          }} <- ReferenceTransaction.fetch_last(tx_address),
         {:ok, cert_pem} <- Map.fetch(json_content, "sslCertificate"),
         %{all_domains: all_domain_names} <-
           EasySSL.parse_pem(cert_pem, all_domains: true),
         true <- match_domain(all_domain_names, domain),
         encrypted_secret_key <-
           Ownership.get_encrypted_key(ownership, Crypto.storage_nonce_public_key()),
         {:ok, secret_key} <-
           Crypto.ec_decrypt_with_storage_nonce(encrypted_secret_key),
         {:ok, key_pem} <- Crypto.aes_decrypt(secret, secret_key) do
      key = key_pem |> read_pem() |> hd()
      cert = cert_pem |> read_pem() |> hd() |> elem(1)

      [key: key, cert: cert]
    else
      _ ->
        https_conf =
          :archethic
          |> Application.get_env(ArchethicWeb.Endpoint)
          |> Keyword.fetch!(:https)

        keyfile = Keyword.fetch!(https_conf, :keyfile)
        certfile = Keyword.fetch!(https_conf, :certfile)

        key_content =
          case File.read(keyfile) do
            {:ok, content} -> content
            {:error, _} -> File.read!(Application.app_dir(:archethic, keyfile))
          end

        cert_content =
          case File.read(certfile) do
            {:ok, content} -> content
            {:error, _} -> File.read!(Application.app_dir(:archethic, certfile))
          end

        key = key_content |> read_pem() |> hd()
        cert = cert_content |> read_pem() |> hd() |> elem(1)

        [key: key, cert: cert]
    end
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

  defp match_domain(all_domain_names, domain) do
    Enum.any?(all_domain_names, fn cert_domain -> do_match_domain(cert_domain, domain) end)
  end

  # Exact domain match
  defp do_match_domain(cert_domain, domain) when cert_domain == domain do
    true
  end

  # Wildcards
  defp do_match_domain("*." <> cert_domain_suffix, domain) do
    String.ends_with?(domain, cert_domain_suffix) and String.split(domain, ".") |> length() > 2
  end

  # no match for other cases
  defp do_match_domain(_, _), do: false
end
