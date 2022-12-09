defmodule ArchethicWeb.Domain do
  @moduledoc """
  Manage AEWeb domain logic
  """

  alias Archethic
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

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

    case :inet_res.lookup('_dnslink.#{dns_name}', :in, :txt,
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
  # sobelow_skip ["Traversal.FileModule"]
  def sni(domain) do
    domain = to_string(domain)

    with {:ok, tx_address} <- lookup_dnslink_address(domain),
         {:ok, tx_address} <- Base.decode16(tx_address, case: :mixed),
         {:ok,
          %Transaction{
            type: :hosting,
            data: %TransactionData{
              content: content,
              ownerships: [ownership = %Ownership{secret: secret} | _]
            }
          }} <-
           Archethic.get_last_transaction(tx_address),
         {:ok, json} <- Jason.decode(content),
         {:ok, cert_pem} <- Map.fetch(json, "sslCertificate"),
         %{extensions: extensions} <- EasySSL.parse_pem(cert_pem),
         {:ok, san} <- Map.fetch(extensions, :subjectAltName),
         ^domain <- String.split(san, ":") |> List.last(),
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
end
