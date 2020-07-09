defmodule Mix.Tasks.CleanPrivDir do
  @moduledoc """
  Task to clean the dev environment to reset the filestorage, last synchronization date
  and storage nonce
  """
  use Mix.Task

  @shortdoc "Clean the uniris_core priv folder for development phase"
  def run(_) do
    File.rm_rf!(Application.app_dir(:uniris_core, "priv/storage"))
    File.rm_rf!(Application.app_dir(:uniris_core, "priv/p2p/last_sync"))
    File.rm(Application.app_dir(:uniris_core, "priv/crypto/storage_nonce"))
  end
end
