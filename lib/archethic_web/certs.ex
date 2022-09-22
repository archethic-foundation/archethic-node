defmodule ArchethicWeb.Certs do
  @moduledoc """
  Manage SSL certificate loading from domain
  """

  alias Archethic.Crypto
  alias Archethic.DB.EmbeddedImpl

  require Logger

  def sni(domain) do
    domain_name = to_string(domain)

    domain_file = Path.join([EmbeddedImpl.db_path(), "hosting/certs", domain_name])

    with {:ok, content} <- File.read(domain_file),
         {:ok, %{"certificate" => cert_pem, "encryptedKey" => encrypted_key}} <-
           Jason.decode(content),
         {:ok, key_pem} <- Crypto.ec_decrypt_with_first_node_key(Base.decode16!(encrypted_key)) do
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

        key = File.read!(keyfile) |> read_pem() |> hd()
        cert = File.read!(certfile) |> read_pem() |> hd() |> elem(1)

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
