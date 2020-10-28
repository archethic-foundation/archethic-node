defmodule Mix.Tasks.CleanPrivDir do
  @moduledoc """
  Task to clean the dev environment to reset the file storage, last synchronization date
  and storage nonce
  """
  use Mix.Task

  @shortdoc "Clean the uniris priv folder for development phase"
  def run(_) do
    IO.puts("Delete local database...")
    File.rm_rf!("priv/storage")

    IO.puts("Delete storage nonce...")
    File.rm_rf!("priv/crypto/storage_nonce")

    IO.puts("Delete last sync snapshots...")
    Path.wildcard("priv/p2p/last_sync*") |> Enum.each(&File.rm_rf!/1)
  end
end
