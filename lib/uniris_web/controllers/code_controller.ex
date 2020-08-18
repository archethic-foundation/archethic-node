defmodule UnirisWeb.CodeController do
  @moduledoc false
  use UnirisWeb, :controller

  def show_proposal(conn, %{"address" => address}) do
    live_render(conn, UnirisWeb.CodeProposalDetailsLive, session: %{"address" => address})
  end

  def download(conn, _) do
    src_dir = Application.get_env(:uniris, :src_dir)
    archive_file = Application.app_dir(:uniris, "priv/uniris_node.zip")
    {_, 0} = System.cmd("git", ["archive", "-o", archive_file, "master"], cd: src_dir)

    conn
    |> put_resp_content_type("application/zip, application/octet-stream")
    |> put_resp_header("Content-disposition", "attachment; filename=\"uniris_node.zip\"")
    |> send_file(200, archive_file)
  end
end
