defmodule UnirisWeb.CodeController do
  @moduledoc false
  use UnirisWeb, :controller

  # alias Uniris.TransactionChain

  # alias UnirisWeb.CodeProposalDetailsLive
  # alias UnirisWeb.ExplorerView

  @src_dir Application.compile_env(:uniris, :src_dir)

  # def show_proposal(conn, %{"address" => address}) do
  #   # case Base.decode16(address, case: :mixed) do
  #   #   {:ok, addr} ->
  #   #     if TransactionChain.transaction_ko?(addr) do
  #   #       conn
  #   #       |> put_view(ExplorerView)
  #   #       |> render("ko_transaction.html", address: addr, errors: [])
  #   #     else
  #   #       live_render(conn, CodeProposalDetailsLive, session: %{"address" => addr})
  #   #     end
  #   #   _ ->
  #       live_render(conn, CodeProposalDetailsLive, session: %{"address" => address})
  #   # end
  # end

  def download(conn, _) do
    archive_file = Application.app_dir(:uniris, "priv/uniris_node.zip")
    {_, 0} = System.cmd("git", ["archive", "-o", archive_file, "master"], cd: @src_dir)

    conn
    |> put_resp_content_type("application/zip, application/octet-stream")
    |> put_resp_header("Content-disposition", "attachment; filename=\"uniris_node.zip\"")
    |> send_file(200, archive_file)
  end
end
