defmodule Uniris.CryptoSupervisor do
  @moduledoc false
  use Supervisor

  alias Uniris.Crypto.Keystore
  alias Uniris.Crypto.LibSodiumPort

  alias Uniris.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children =
      [LibSodiumPort] ++
        Utils.configurable_children([
          {Keystore, [], []}
        ])

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
