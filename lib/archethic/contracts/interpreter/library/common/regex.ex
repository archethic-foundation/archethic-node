defmodule Archethic.Contracts.Interpreter.Library.Common.Regex do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Legacy

  @spec match?(binary(), binary()) :: boolean()
  defdelegate match?(text, pattern),
    to: Legacy.Library,
    as: :regex_match?

  @spec extract(binary(), binary()) :: binary()
  defdelegate extract(text, pattern),
    to: Legacy.Library,
    as: :regex_extract

  @doc """
  Extract data from string using capture groups
  (multiline flag is activated)

  ps: the number of antislash is doubled because this is a doctest

  ## Examples

      iex> Regex.scan("foo", "bar")
      []

      iex> Regex.scan("toto,123\\ntutu,456\\n", "toto,([0-9]+)")
      ["123"]

      iex> Regex.scan("toto,123\\ntutu,456\\n", "t.t.,([0-9]+)")
      ["123", "456"]

      iex> Regex.scan("A0B1C2,123\\nD3E4F5,456\\n", "^(\\\\w+),(\\\\d+)$")
      [["A0B1C2", "123"], ["D3E4F5", "456"]]

  """
  @spec scan(binary(), binary()) :: list(binary())
  def scan(text, pattern) when is_binary(text) and is_binary(pattern) do
    case Regex.compile(pattern, "m") do
      {:ok, pattern} ->
        Regex.scan(pattern, text, capture: :all_but_first)
        |> Enum.map(fn
          [item] -> item
          other -> other
        end)

      _ ->
        []
    end
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:extract, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:match?, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:scan, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(_, _), do: false
end
