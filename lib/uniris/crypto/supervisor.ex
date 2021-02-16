defmodule Uniris.Crypto.Supervisor do
  @moduledoc false
  use Supervisor

  alias Uniris.Crypto
  alias Uniris.Crypto.Ed25519.LibSodiumPort

  alias Uniris.Crypto.Keystore
  alias Uniris.Crypto.KeystoreLoader

  alias Uniris.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.CryptoSupervisor)
  end

  def init(_args) do
    load_storage_nonce()

    optional_children = [keystore_child_spec(), KeystoreLoader]
    children = [LibSodiumPort | Utils.configurable_children(optional_children)]
    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp keystore_child_spec do
    keystore_impl = Application.get_env(:uniris, Keystore)[:impl]
    {Keystore, Application.get_env(:uniris, keystore_impl)}
  end

  defp load_storage_nonce do
    abs_filepath = Crypto.storage_nonce_filepath()
    File.mkdir_p(abs_filepath)

    case File.read(abs_filepath) do
      {:ok, storage_nonce} ->
        :persistent_term.put(:storage_nonce, storage_nonce)

      _ ->
        :ok
    end
  end
end
