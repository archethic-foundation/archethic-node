defmodule Mix.Tasks.CleanPrivDir do
  use Mix.Task

  @shortdoc "Clean the uniris_core priv folder for development phase"
  def run(_) do
    File.rm_rf!(Application.app_dir(:uniris_core, "priv/storage"))
    File.rm_rf!(Application.app_dir(:uniris_core, "priv/last_sync"))
  end
end
