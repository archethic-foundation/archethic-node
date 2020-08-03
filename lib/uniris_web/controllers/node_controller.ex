defmodule UnirisWeb.NodeController do
  use UnirisWeb, :controller

  alias Uniris.Crypto
  alias Uniris.P2P
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  def index(conn, _params) do
    render(conn, "index.html", nodes: P2P.list_nodes())
  end

  def show(conn, _params = %{"public_key" => public_key}) do
    pub = Base.decode16!(public_key, case: :mixed)

    case P2P.node_info(pub) do
      {:ok, node} ->
        node_address = Crypto.hash(pub)

        inputs =
          node_address
          |> Uniris.get_transaction_inputs()
          |> Enum.filter(&(&1.amount > 0.0))
          |> Enum.reduce(%{}, fn %UnspentOutput{from: from, amount: amount}, acc ->
            Map.update(acc, from, amount, &(&1 + amount))
          end)

        balance = Uniris.get_balance(node_address)
        render(conn, "show.html", inputs: inputs, node: node, balance: balance)

      _ ->
        render(conn, "show.html", inputs: [], node: nil, balance: 0.0)
    end
  end
end
