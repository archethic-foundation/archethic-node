defmodule Archethic.Contracts.Interpreter do
  @moduledoc false

  require Logger

  alias __MODULE__.Version0
  alias __MODULE__.Version1

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions, as: Conditions

  alias Archethic.TransactionChain.Transaction

  @type version() :: {integer(), integer(), integer()}

  @doc """
  Dispatch through the correct interpreter.
  This return a filled contract structure or an human-readable error.
  """
  @spec parse(code :: binary()) :: {:ok, Contract.t()} | {:error, String.t()}
  def parse(code) when is_binary(code) do
    case version(code) do
      {{0, 0, 1}, code_without_version} ->
        Version0.parse(code_without_version)

      {version = {1, _, _}, code_without_version} ->
        Version1.parse(code_without_version, version)

      _ ->
        {:error, "@version not supported"}
    end
  end

  @doc """
  Sanitize code takes care of converting atom to {:atom, bin()}.
  This way the user cannot create atoms at all. (which is mandatory to avoid atoms-table exhaustion)
  """
  @spec sanitize_code(binary()) :: {:ok, Macro.t()} | {:error, any()}
  def sanitize_code(code) when is_binary(code) do
    code
    |> String.trim()
    |> Code.string_to_quoted(static_atoms_encoder: &atom_encoder/2)
  end

  @doc """
  Determine from the code, the version to use.
  Return the version & the code where the version has been removed.
  (should be private, but there are unit tests)
  """
  @spec version(String.t()) :: {version(), String.t()} | :error
  def version(code) do
    regex_opts = [capture: :all_but_first]

    version_attr_regex = ~r/^\s*@version\s+"(\S+)"/

    if Regex.match?(~r/^\s*@version/, code) do
      case Regex.run(version_attr_regex, code, regex_opts) do
        nil ->
          # there is a @version but syntax is invalid (probably the quotes missing)
          :error

        [capture] ->
          case Regex.run(semver_regex(), capture, regex_opts) do
            nil ->
              # there is a @version but semver syntax is wrong
              :error

            ["0", "0", "0"] ->
              # there is a @version but it's 0.0.0
              :error

            [major, minor, patch] ->
              {
                {String.to_integer(major), String.to_integer(minor), String.to_integer(patch)},
                Regex.replace(version_attr_regex, code, "")
              }
          end
      end
    else
      # no @version at all
      {{0, 0, 1}, code}
    end
  end

  @doc """
  Return true if the given conditions are valid on the given constants
  """
  @spec valid_conditions?(version(), Conditions.t(), map()) :: bool()
  def valid_conditions?({0, _, _}, conditions, constants) do
    Version0.valid_conditions?(conditions, constants)
  end

  def valid_conditions?({1, _, _}, conditions, constants) do
    Version1.valid_conditions?(conditions, constants)
  end

  @doc """
  Execute the trigger/action code.
  May return a new transaction or nil
  """
  @spec execute_trigger(version(), Macro.t(), map()) :: Transaction.t() | nil
  def execute_trigger({0, _, _}, ast, constants) do
    Version0.execute_trigger(ast, constants)
  end

  def execute_trigger({1, _, _}, ast, constants) do
    Version1.execute_trigger(ast, constants)
  end

  @doc """
  Format an error message from the failing ast node

  It returns message with metadata if possible to indicate the line of the error
  """
  @spec format_error_reason(any(), String.t()) :: String.t()
  def format_error_reason({:atom, _key}, reason) do
    do_format_error_reason(reason, "", [])
  end

  def format_error_reason({{:atom, key}, metadata, _}, reason) do
    do_format_error_reason(reason, key, metadata)
  end

  def format_error_reason({_, metadata, [{:__aliases__, _, [atom: module]} | _]}, reason) do
    do_format_error_reason(reason, module, metadata)
  end

  def format_error_reason(ast_node = {_, metadata, _}, reason) do
    # FIXME: Macro.to_string will not work on all nodes due to {:atom, bin()}
    do_format_error_reason(reason, Macro.to_string(ast_node), metadata)
  end

  def format_error_reason({{:atom, _}, {_, metadata, _}}, reason) do
    do_format_error_reason(reason, "", metadata)
  end

  def format_error_reason({{:atom, key}, _}, reason) do
    do_format_error_reason(reason, key, [])
  end

  defp do_format_error_reason(message, cause, metadata) do
    message = prepare_message(message)

    [prepare_message(message), cause, metadata_to_string(metadata)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" - ")
  end

  defp prepare_message(message) when is_atom(message) do
    message |> Atom.to_string() |> String.replace("_", " ")
  end

  defp prepare_message(message) when is_binary(message) do
    String.trim_trailing(message, ":")
  end

  defp metadata_to_string(line: line, column: column), do: "L#{line}:C#{column}"
  defp metadata_to_string(line: line), do: "L#{line}"
  defp metadata_to_string(_), do: ""

  defp atom_encoder(atom, _) do
    if atom in ["if"] do
      {:ok, String.to_atom(atom)}
    else
      {:ok, {:atom, atom}}
    end
  end

  # source: https://semver.org/
  defp semver_regex() do
    ~r/(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?/
  end
end
