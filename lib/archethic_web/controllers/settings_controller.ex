defmodule ArchethicWeb.SettingsController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Reward

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer

  plug(:enabled)

  @ip_validate_regex ~r/(^127\.)|(^192\.168\.)/

  defp enabled(conn = %Plug.Conn{remote_ip: remote_ip}, _) do
    private_ip? =
      Regex.match?(
        @ip_validate_regex,
        :inet.ntoa(remote_ip) |> to_string()
      )

    # Only authorized the page in the node's private network
    if private_ip? do
      conn
    else
      conn
      |> put_status(:not_found)
      |> put_view(ArchethicWeb.ErrorView)
      |> render("404.html")
      |> halt()
    end
  end

  def index(conn, _) do
    %Node{reward_address: reward_address} = P2P.get_node_info()

    render(conn, "index.html", reward_address: Base.encode16(reward_address))
  end

  def save(conn, params) do
    with {:ok, reward_address} <- Map.fetch(params, "reward_address"),
         {:ok, reward_address_bin} <- Base.decode16(reward_address, case: :mixed),
         true <- Crypto.valid_address?(reward_address_bin) do
      %Node{
        ip: ip,
        port: port,
        http_port: http_port,
        transport: transport,
        reward_address: reward_address
      } = P2P.get_node_info()

      {:ok, last_address} = Archethic.get_last_transaction_address(reward_address)
      {:ok, %{token: tokens}} = Archethic.get_balance(last_address)

      token_transfers =
        tokens
        |> Enum.filter(fn {{address, _}, _} -> Reward.is_reward_token?(address) end)
        |> Enum.map(fn {{address, token_id}, amount} ->
          %TokenTransfer{
            to: reward_address_bin,
            amount: amount,
            token_id: token_id,
            token_address: address
          }
        end)

      Transaction.new(:node, %TransactionData{
        ledger: %Ledger{
          token: %TokenLedger{
            transfers: token_transfers
          }
        },
        code: """
          condition inherit: [
            # We need to ensure the type stays consistent
            type: node,
          
            # Content and token transfers will be validated during tx's validation
            content: true,
            token_transfers: true
          ]
        """,
        content:
          Node.encode_transaction_content(
            ip,
            port,
            http_port,
            transport,
            reward_address_bin,
            Crypto.origin_node_public_key(),
            Crypto.get_key_certificate(Crypto.origin_node_public_key())
          )
      })
      |> Archethic.send_new_transaction()

      render(conn, "index.html", reward_address: Base.encode16(reward_address_bin))
    else
      _ ->
        %Node{reward_address: reward_address} = P2P.get_node_info()
        render(conn, "index.html", reward_address: Base.encode16(reward_address))
    end
  end
end
