defmodule Migration_1_2_2 do
  @moduledoc """
  Serialize burned_fees & nb_transactions on 8 bytes instead of 4.
  """

  alias Archethic.Utils

  def run() do
    db_path = Utils.mut_dir()
    filepath = Path.join(db_path, "stats")
    filepath_backup = Path.join(db_path, "stats.backup")

    # make a backup
    :ok = File.rename(filepath, filepath_backup)

    # open 2 file descriptors
    fd_old = File.open!(filepath_backup, [:binary, :read])
    fd_new = File.open!(filepath, [:binary, :append])

    :ok = migrate_line(fd_old, fd_new)
    File.close(fd_old)
    File.close(fd_new)

    # remove backup
    File.rm(filepath_backup)
  end

  defp migrate_line(fd_old, fd_new) do
    # Read 20 bytes from old
    case :file.read(fd_old, 20) do
      {:ok, <<timestamp::32, tps::float-64, nb_transactions::32, burned_fees::32>>} ->
        # Write 28 bytes to new
        :ok = IO.binwrite(fd_new, <<timestamp::32, tps::float-64, nb_transactions::64, burned_fees::64>>)
        migrate_line(fd_old, fd_new)

      :eof ->
        :ok
    end
  end
end
