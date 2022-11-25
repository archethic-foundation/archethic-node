defmodule ArchethicWeb.API.WebHosting.CheckSum do
  @moduledoc """
  Orchestrate the retrieval of checksum for a Reference Transaction
  """

  use ArchethicWeb, :controller

  alias Archethic

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  def get_checksum(ref_address_bin) do
    with {:ok, ref_txn} <- Archethic.search_transaction(ref_address_bin),
         %Transaction{data: %TransactionData{content: content}} <- ref_txn,
         {:ok, json_data} <- Jason.decode(content),
         {:ok, file_path_to_addr} <- file_to_address(json_data),
         {:ok, txn_map} <- txn_to_fetch(file_path_to_addr),
         {:ok, txn_addr_to_content} <- fetch_txn(txn_map),
         {:ok, file_to_hash} <- file_to_hash(file_path_to_addr, txn_addr_to_content) do
      {:data, file_to_hash}
    else
      {:error, :network_error} ->
        "Network Error"

      e ->
        e
    end
  end

  def display(x, label) do
    IO.inspect(x, label: label, limit: :infinity)
  end

  def file_to_hash(file_path_to_addr, txn_addr_to_content) do
    addr_to_path_to_content =
      Enum.reduce(
        txn_addr_to_content,
        %{},
        fn {txn_addr, content}, acc ->
          Map.put(acc, txn_addr, path_to_content(content))
        end
      )

    {:ok,
     file_path_to_addr
     |> build_content(addr_to_path_to_content)
     |> build_checksum()}
  end

  def build_checksum(path_to_content) do
    path_to_content
    |> Enum.reduce(%{}, fn {path, content}, acc ->
      Map.put(acc, path, Base.encode16(:crypto.hash(:sha, content)))
    end)
  end

  def build_content(file_path_to_addr, addr_to_path_to_content) do
    file_path_to_addr
    |> Enum.reduce(%{}, fn {path, addresses}, acc ->
      content =
        Enum.map_join(addresses, fn address ->
          addr_to_path_to_content
          |> Map.get(address)
          |> Map.get(path)
        end)

      Map.put(acc, path, content)
    end)
  end

  def path_to_content(files_map) do
    file_path_to_content(Enum.to_list(files_map), %{}, "")
    |> Enum.sort()
    |> Map.new()
  end

  def file_path_to_content([], res_acc, _headpath) do
    res_acc
  end

  def file_path_to_content([{k, value} | rest], res_acc, headpath) when is_binary(value) do
    res_acc = Map.put(res_acc, headpath <> k, value)
    file_path_to_content(rest, res_acc, headpath)
  end

  def file_path_to_content([{k, another_map} | rest], res_acc, headpath)
      when is_map(another_map) do
    new_acc = file_path_to_content(Enum.to_list(another_map), res_acc, headpath <> k <> "/")
    file_path_to_content(rest, new_acc, headpath)
  end

  def txn_to_fetch(file_list) do
    {:ok,
     Enum.reduce(file_list, %{}, fn {_, address_list}, acc ->
       Enum.reduce(address_list, acc, &Map.put(&2, &1, nil))
     end)}
  end

  def fetch_txn(txn_map) do
    txn_to_content =
      Task.Supervisor.async_stream_nolink(
        Archethic.TaskSupervisor,
        txn_map,
        fn {txn_addr, nil} ->
          json_content =
            try do
              {:ok, %Transaction{data: %TransactionData{content: content}}} =
                Base.decode16!(txn_addr, case: :mixed) |> Archethic.search_transaction()

              {:ok, json_content} = Jason.decode(content)
              json_content
            rescue
              _ -> :error
            end

          %{txn_addr => json_content}
        end,
        ordered: false,
        on_timeout: :kill_task,
        timeout: 3_000
      )
      |> Enum.reduce(%{}, fn {:ok, data}, acc ->
        [{txn_addr, content_map}] = Enum.to_list(data)
        Map.put(acc, txn_addr, content_map)
      end)

    all_values? =
      Enum.any?(txn_to_content, fn
        {_, :error} ->
          true

        {_, _} ->
          false
      end)

    status =
      case all_values? do
        false -> :ok
        true -> :network_error
      end

    {status, txn_to_content}
  end

  def file_to_address(files_map) do
    {:ok,
     file_path_to_address(Enum.to_list(files_map), %{}, "")
     |> Enum.sort()}
  end

  def file_path_to_address([], res_acc, _headpath) do
    res_acc
  end

  def file_path_to_address(
        [{k, %{"address" => address_list, "encodage" => _encodings}} | rest],
        res_acc,
        headpath
      ) do
    res_acc = Map.put(res_acc, headpath <> k, address_list)
    file_path_to_address(rest, res_acc, headpath)
  end

  def file_path_to_address([{k, another_map} | rest], res_acc, headpath) do
    new_acc = file_path_to_address(Enum.to_list(another_map), res_acc, headpath <> k <> "/")
    file_path_to_address(rest, new_acc, headpath)
  end
end
