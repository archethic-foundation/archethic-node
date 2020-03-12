defmodule UnirisCrypto.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do

    children = [
      :poolboy.child_spec(:libsodium, poolboy_config()),
      {UnirisCrypto.Keystore,
       [
         seed: Application.get_env(:uniris_crypto, :seed)
       ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp poolboy_config do
    [
      name: {:local, :libsodium},
      worker_module: UnirisCrypto.LibSodiumPort,
      size: 5,
      max_overflow: 2
    ]
  end
end
