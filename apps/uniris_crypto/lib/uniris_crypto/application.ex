defmodule UnirisCrypto.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      UnirisCrypto.SoftwareImpl.Supervisor,
      {UnirisCrypto.SoftwareImpl,
       [
         seed: Application.get_env(:uniris_crypto, :seed)
       ]},
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
