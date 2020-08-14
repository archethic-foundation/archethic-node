defmodule UnirisWeb.CodeController do
  @moduledoc false
  use UnirisWeb, :controller

  alias Uniris.Governance.Git
  alias Uniris.Governance.ProposalMetadata

  alias Uniris.Storage

  def show_proposal(conn, %{"address" => address}) do
    {:ok, tx} = Storage.get_transaction(Base.decode16!(address, case: :mixed))

    render(conn, "proposal_detail.html",
      address: address,
      changes: ProposalMetadata.get_changes(tx.content),
      description: ProposalMetadata.get_description(tx.content)
    )
  end

  def download(conn, _) do
    files =
      Git.list_branch_files("master")
      |> Enum.map(&String.to_charlist/1)

    root_dir = Application.get_env(:uniris, :src_dir)

    {:ok, {filename, data}} = :zip.create("uniris_node.zip", files, [:memory, cwd: root_dir])

    conn
    |> put_resp_content_type("application/zip, application/octet-stream")
    |> put_resp_header("Content-disposition", "attachment; filename=\"#{filename}\"")
    |> put_resp_header("content-encoding", "gzip")
    |> send_resp(200, :zlib.gzip(data))
  end
end
