defmodule Uniris.P2P.Endpoint.AcceptorSupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.P2P.Transport

  @default_nb_acceptors 10

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    transport = Keyword.get(args, :transport)
    nb_acceptors = Keyword.get(args, :nb_acceptors, @default_nb_acceptors)
    listen_socket = Keyword.get(args, :listen_socket)

    children = Enum.map(1..nb_acceptors, &child_spec(transport, listen_socket, &1))

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp child_spec(transport, listen_socket, acceptor_id) do
    %{
      id: {:acceptor, acceptor_id},
      start: {Task, :start_link, [Transport, :accept, [transport, listen_socket]]}
    }
  end
end
