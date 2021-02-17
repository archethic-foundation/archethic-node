defmodule Uniris.Oracles.TransactionContent do
  @moduledoc false

  defstruct [
    :mfa,
    :payload
  ]

  def serialize(%__MODULE__{mfa: {m, f, a}, payload: payload}) do
    m_binary = :erlang.atom_to_binary(m)
    f_binary = :erlang.atom_to_binary(f)

    a_binary =
      a
      |> Enum.map_join("&", fn {k, v} -> "#{k}|#{v}" end)

    <<byte_size(m_binary)::8, m_binary::binary, byte_size(f_binary)::8, f_binary::binary,
      byte_size(a_binary)::8, a_binary::binary, payload::binary>>
  end

  def deserialize(
        <<m_size::8, m_str::binary-size(m_size), f_size::8, f_str::binary-size(f_size), a_size::8,
          a_str::binary-size(a_size), payload::binary>>
      ) do
    args =
      a_str
      |> String.split("&")
      |> Enum.reduce([], fn arg, acc ->
        [k_str, v] =
          arg
          |> String.split("|")

        k = String.to_atom(k_str)

        v =
          cond do
            k == :date -> elem(DateTime.from_iso8601(v), 1)
            true -> v
          end

        [{k, v} | acc]
      end)

    module = String.to_atom(m_str)
    fun = String.to_atom(f_str)

    %__MODULE__{mfa: {module, fun, args}, payload: payload}
  end
end
