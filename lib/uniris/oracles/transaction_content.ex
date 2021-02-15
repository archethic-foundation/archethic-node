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
      |> Enum.map_join("&", fn {k, v} -> "#{k}:#{v}" end)

    <<byte_size(m_binary)::8, m_binary::binary, byte_size(f_binary)::8, f_binary::binary,
      byte_size(a_binary)::8, a_binary::binary, payload::binary>>
  end

  def deserialize(
        <<m_size::8, m::binary-size(m_size), f_size::8, f::binary-size(f_size), a_size::8,
          a::binary-size(a_size), payload_binary::binary>>
      ) do
    IO.puts("DESERIALIZE MSIZE: #{inspect(m_size)}")
    IO.puts("DESERIALIZE M: #{inspect(m)}")
    IO.puts("DESERIALIZE FSIZE: #{inspect(f_size)}")
    IO.puts("DESERIALIZE F: #{inspect(f)}")
    IO.puts("DESERIALIZE ASIZE: #{inspect(a_size)}")
    IO.puts("DESERIALIZE A: #{inspect(a)}")
    IO.puts("DESERIALIZE PAYLOAD BINARY: #{inspect(payload_binary)}")

    a =
      a
      |> Enum.chunk(2)
      |> Map.new(fn [k, v] -> {k, v} end)

    IO.puts("DESERIALIZE PAYLOAD: #{inspect(a)}")

    # IO.puts "DESERIALIZE MFA: #{inspect mfa}"
    # IO.puts "DESERIALIZE PAYLOAD: #{inspect payload}"
    # {
    #   %__MODULE__{mfa: mfa, payload: payload}
    # }
  end
end
