defmodule Migration_1_2_4 do
  @moduledoc """
  Erase stats file to keep only values of last beacon summary
  """

  alias Archethic.DB

  def run() do
    db_path = DB.filepath()
    filepath = Path.join(db_path, "stats")
    filepath_backup = Path.join(db_path, "stats.backup")

    # make a backup
    :ok = File.rename(filepath, filepath_backup)

    fd = File.open!(filepath_backup)

    {last_update, tps, nb_transactions, burned_fees} = load_from_file(fd)

    File.write!(
      filepath,
      <<DateTime.to_unix(last_update)::32, tps::float-64, nb_transactions::64, burned_fees::64>>
    )

    # remove backup
    File.rm(filepath_backup)
  end

  defp load_from_file(fd, acc \\ {nil, 0.0, 0, 0}) do
    # Read each stats entry 28 bytes: 4(timestamp) + 8(tps) + 8(nb transactions) + 8(burned_fees)
    case :file.read(fd, 28) do
      {:ok, <<timestamp::32, tps::float-64, nb_transactions::64, burned_fees::64>>} ->
        {_, _, prev_nb_transactions, _} = acc

        load_from_file(
          fd,
          {DateTime.from_unix!(timestamp), tps, prev_nb_transactions + nb_transactions,
           burned_fees}
        )

      :eof ->
        acc
    end
  end
end
