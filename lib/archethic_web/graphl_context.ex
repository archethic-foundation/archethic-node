defmodule ArchethicWeb.GraphQLContext do
  @moduledoc false

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _) do
    context = build_context(conn)
    Absinthe.Plug.put_options(conn, context: context)
  end

  def build_context(conn) do
    %{ip: conn.remote_ip}
  end
end
