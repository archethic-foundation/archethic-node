defmodule Archethic.Contracts.Interpreter.Legacy.Library do
  @moduledoc false

  alias Archethic.{
    Election,
    P2P,
    P2P.Message.GetFirstPublicKey,
    P2P.Message.FirstPublicKey,
    TransactionChain,
    Utils
  }

  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter

  require Logger

  @doc """
  Match a regex expression

  ## Examples

      iex> Library.regex_match?("abcdef024894", "^[a-z0-9]+$")
      true

      iex> Library.regex_match?("sfdl#@", "^[a-z0-9]+$")
      false
  """
  @spec regex_match?(binary(), binary()) :: boolean()
  def regex_match?(text, pattern) when is_binary(text) and is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, pattern} ->
        Regex.match?(pattern, text)

      _ ->
        false
    end
  end

  @doc """
  Extract data from a regex expression

  ## Examples

      iex> Library.regex_extract("abcdef024894", "^[a-z0-9]+$")
      "abcdef024894"

      iex> Library.regex_extract("sfdl#@", "^[a-z0-9]+$")
      ""

      iex> Library.regex_extract("sfdl#@", "[a-z0-9]+")
      "sfdl"
  """
  @spec regex_extract(binary(), binary()) :: binary()
  def regex_extract(text, pattern) when is_binary(text) and is_binary(pattern) do
    with {:ok, pattern} <- Regex.compile(pattern),
         [res] <- Regex.run(pattern, text) do
      res
    else
      _ ->
        ""
    end
  end

  @doc ~S"""
  Extract data from a JSON path expression

  ## Examples

      iex> Library.json_path_extract(
      ...>   "{ \"firstName\": \"John\", \"lastName\": \"Doe\"}",
      ...>   "$.firstName"
      ...> )
      "John"

      iex> Library.json_path_extract("{ \"firstName\": \"John\", \"lastName\": \"Doe\"}", "$.book")
      ""

  """
  @spec json_path_extract(binary(), binary()) :: binary()
  def json_path_extract(text, path) when is_binary(text) and is_binary(path) do
    res =
      text
      |> Jason.decode!()
      |> ExJSONPath.eval(path)

    case res do
      {:ok, [res | _]} ->
        res

      _ ->
        ""
    end
  end

  @doc ~S"""
  Match a json path expression

  ## Examples

       iex> Library.json_path_match?(
       ...>   "{\"1622541930\":{\"uco\":{\"eur\":0.176922,\"usd\":0.21642}}}",
       ...>   "$.*.uco.usd"
       ...> )
       true
  """
  @spec json_path_match?(binary(), binary()) :: boolean()
  def json_path_match?(text, path) when is_binary(text) and is_binary(path) do
    case json_path_extract(text, path) do
      "" ->
        false

      _ ->
        true
    end
  end

  @doc """
  Hash a content

  ## Examples

      iex> Library.hash("hello", "sha256")
      "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"

      iex> Library.hash("hello")
      "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"
  """
  @spec hash(
          content :: binary(),
          algo :: binary()
        ) ::
          binary()
  def hash(content, algo \\ "sha256") when is_binary(content) do
    algo =
      case algo do
        "sha256" ->
          :sha256

        "sha512" ->
          :sha512

        "sha3_256" ->
          :sha3_256

        "sha3_512" ->
          :sha3_512

        "blake2b" ->
          :blake2b
      end

    :crypto.hash(algo, UtilsInterpreter.maybe_decode_hex(content))
    |> Base.encode16()
  end

  @doc """
  Determines if the value is inside the list

  ## Examples

      iex> Library.in?("hello", ["hi", "hello"])
      true

      iex> Library.in?(["a", "b"], ["a", "c", "b"])
      true
  """
  @spec in?(any(), list()) :: boolean()
  def in?(val, list) when is_list(val) and is_list(list) do
    Enum.all?(val, &(&1 in list))
  end

  def in?(val, list) when is_list(list) do
    val in list
  end

  @doc """
  Determines the size  of the input

  ## Examples

      iex> Library.size("hello")
      5

      iex> Library.size([1, 2, 3])
      3

      iex> Library.size(%{"a" => 1, "b" => 2})
      2
  """
  @spec size(binary() | list()) :: non_neg_integer()
  def size(binary) when is_binary(binary),
    do: binary |> UtilsInterpreter.maybe_decode_hex() |> byte_size()

  def size(list) when is_list(list), do: length(list)
  def size(map) when is_map(map), do: map_size(map)

  @doc """
  Get the genesis public key
  """
  @spec get_genesis_public_key(binary()) :: binary()
  def get_genesis_public_key(address) do
    bin_address = UtilsInterpreter.maybe_decode_hex(address)
    nodes = Election.chain_storage_nodes(bin_address, P2P.authorized_and_available_nodes())
    {:ok, key} = download_first_public_key(nodes, bin_address)
    Base.encode16(key)
  end

  defp download_first_public_key([node | rest], public_key) do
    case P2P.send_message(node, %GetFirstPublicKey{public_key: public_key}) do
      {:ok, %FirstPublicKey{public_key: key}} -> {:ok, key}
      {:ok, _} -> download_first_public_key(rest, public_key)
      {:error, _} -> download_first_public_key(rest, public_key)
    end
  end

  defp download_first_public_key([], _address), do: {:error, :network_issue}

  @doc """
  Return the current UNIX timestamp
  """
  @spec timestamp() :: non_neg_integer()
  def timestamp, do: DateTime.utc_now() |> DateTime.to_unix()

  @doc """
  Provide a token id which uniquely identify the token base on it's properties and genesis address.
  """
  @spec get_token_id(binary()) :: {:error, binary()} | binary()
  def get_token_id(address) do
    address = UtilsInterpreter.get_address(address, :get_token_id)
    t1 = Task.async(fn -> Archethic.fetch_genesis_address(address) end)
    t2 = Task.async(fn -> Archethic.search_transaction(address) end)

    with {:ok, {:ok, genesis_address}} <- Task.yield(t1),
         {:ok, {:ok, tx}} <- Task.yield(t2),
         {:ok, %{id: id}} <- Utils.get_token_properties(genesis_address, tx) do
      id
    else
      {:ok, {:error, :network_issue}} ->
        {:error, "Network issue"}

      {:ok, {:error, :transaction_not_exists}} ->
        {:error, "Transaction not exists"}

      {:error, :decode_error} ->
        {:error, "Error in decoding transaction"}

      {:error, :not_a_token_transaction} ->
        {:error, "Transaction is not of type token"}

      {:exit, reason} ->
        Logger.debug("Task exited with reason #{inspect(reason)}")
        {:error, "Task Exited!"}

      nil ->
        {:error, "Task didn't responded within timeout!"}
    end
  end

  @doc """
  Get the genesis address of the chain
  """
  @spec get_genesis_address(binary()) ::
          binary()
  def get_genesis_address(address) do
    addr_bin = UtilsInterpreter.maybe_decode_hex(address)
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_genesis_address(addr_bin, nodes) do
      {:ok, genesis_address} -> Base.encode16(genesis_address)
      {:error, reason} -> raise "[get_genesis_address]  #{inspect(reason)}"
    end
  end

  @doc """
  Get the First transaction address of the transaction chain for the given address
  """
  @spec get_first_transaction_address(address :: binary()) ::
          binary()
  def get_first_transaction_address(address) do
    addr_bin = UtilsInterpreter.maybe_decode_hex(address)
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_first_transaction_address(addr_bin, nodes) do
      {:ok, first_transaction_address} -> Base.encode16(first_transaction_address)
      {:error, reason} -> raise "[get_first_transaction_address]  #{inspect(reason)}"
    end
  end
end
