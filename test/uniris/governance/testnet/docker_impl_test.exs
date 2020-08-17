defmodule Uniris.Governance.Testnet.DockerImplTest do
  use ExUnit.Case

  alias Uniris.Governance.Testnet
  alias Uniris.Governance.Testnet.DockerImpl, as: Docker

  import Mox

  @tag infrastructure: true
  test "deploy/4 should create a running docker instance" do
    MockCommandLogger
    |> stub(:write, fn data, _ ->
      IO.write("#{data}\n")
    end)

    p2p_port = 45_000
    web_port = 20_000

    p2p_seeds =
      "127.0.0.1:#{p2p_port}:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"

    :ok = Docker.deploy("@CodeChanges1", p2p_port, web_port, p2p_seeds)

    Process.sleep(3_000)

    assert :ok = Testnet.healthcheck(web_port)

    "@CodeChanges1"
    |> Docker.image_name()
    |> Docker.clean_image()
  end
end
