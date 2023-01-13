defmodule Archethic.Crypto.Keccak do
  @moduledoc """
    To be removed after stable OPENSSL #3.2
  """
  require Bitwise
  require Record

  @compile :inline_list_funcs
  @compile {:inline_unroll, 24}
  @compile {:inline_effort, 500}
  @compile {:inline_size, 1000}
  @compile {
    :inline,
    rho: 1, pi: 1, rc: 1, rol: 2, for_n: 4, binary_a64: 2, xor: 2, bnot: 1, band: 2
  }
  @rho {1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44}
  @pi {10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1}
  @rc {1, 0x8082, 0x800000000000808A, 0x8000000080008000, 0x808B, 0x80000001, 0x8000000080008081,
       0x8000000000008009, 0x8A, 0x88, 0x80008009, 0x8000000A, 0x8000808B, 0x800000000000008B,
       0x8000000000008089, 0x8000000000008003, 0x8000000000008002, 0x8000000000000080, 0x800A,
       0x800000008000000A, 0x8000000080008081, 0x8000000000008080, 0x80000001, 0x8000000080008008}

  @zero64 0
  @full64 0xFFFFFFFFFFFFFFFF

  defp rho(index), do: elem(@rho, index)
  defp pi(index), do: elem(@pi, index)
  defp rc(index), do: elem(@rc, index)

  defp rol(x, s) do
    x = Bitwise.bsl(x, s)
    y = Bitwise.bsr(x, 64)
    band(x, @full64) + y
  end

  defp for_n(n, step, acc, fun) do
    :lists.foldl(
      fn i, acc ->
        fun.(i * step, acc)
      end,
      acc,
      :lists.seq(0, n - 1)
    )
  end

  defp binary_a64(<<bin::little-unsigned-size(64), rest::binary>>, tuple) do
    binary_a64(rest, Tuple.append(tuple, bin))
  end

  defp binary_a64("", tuple) do
    tuple
  end

  defp a64_binary(tuple) do
    Tuple.to_list(tuple)
    |> Enum.map(fn num -> <<num::little-unsigned-size(64)>> end)
    |> :erlang.iolist_to_binary()
  end

  def xor(a, b) do
    Bitwise.bxor(a, b)
  end

  # defp bnot(a), do: xor(a, @full64)
  defp bnot(a), do: xor(a, @full64)

  defp band(a, b), do: Bitwise.band(a, b)

  Record.defrecord(:calc,
    inbin: {@zero64, @zero64, @zero64, @zero64, @zero64},
    t: @zero64,
    state: nil
  )

  defp keccakf(a) do
    state = binary_a64(a, {})
    # acc = {a, inbin}
    acc = calc(state: state)

    for_n(24, 1, acc, fn i, acc ->
      # // Theta
      acc =
        for_n(5, 1, acc, fn x, acc = calc(inbin: inbin) ->
          inbin = put_elem(inbin, x, @zero64)
          acc = calc(acc, inbin: inbin)

          for_n(5, 5, acc, fn y, acc = calc(state: state, inbin: inbin) ->
            ret = xor(elem(inbin, x), elem(state, x + y))
            inbin = put_elem(inbin, x, ret)
            calc(acc, inbin: inbin)
          end)
        end)

      calc(state: state, inbin: inbin) =
        for_n(5, 1, acc, fn x, acc ->
          for_n(5, 5, acc, fn y, acc = calc(state: state, inbin: inbin) ->
            ret =
              xor(elem(inbin, rem(x + 4, 5)), rol(elem(inbin, rem(x + 1, 5)), 1))
              |> xor(elem(state, y + x))

            state = put_elem(state, x + y, ret)
            calc(acc, state: state)
          end)
        end)

      # // Rho and pi
      acc = calc(t: elem(state, 1), state: state, inbin: inbin)

      acc =
        for_n(24, 1, acc, fn x, calc(state: state, inbin: inbin, t: t) ->
          inbin = put_elem(inbin, 0, elem(state, pi(x)))
          state = put_elem(state, pi(x), rol(t, rho(x)))
          calc(t: elem(inbin, 0), state: state, inbin: inbin)
        end)

      # // Chi
      acc =
        calc(state: state) =
        for_n(5, 5, acc, fn y, acc ->
          acc =
            for_n(5, 1, acc, fn x, acc = calc(state: state, inbin: inbin) ->
              inbin = put_elem(inbin, x, elem(state, y + x))
              calc(acc, inbin: inbin)
            end)

          for_n(5, 1, acc, fn x, acc = calc(state: state, inbin: inbin) ->
            ret =
              bnot(elem(inbin, rem(x + 1, 5)))
              |> band(elem(inbin, rem(x + 2, 5)))
              |> xor(elem(inbin, x))

            state = put_elem(state, y + x, ret)
            calc(acc, state: state)
          end)
        end)

      # // Iota
      state = put_elem(state, 0, xor(elem(state, 0), rc(i)))
      calc(acc, state: state)
    end)
    |> calc(:state)
    |> a64_binary()
  end

  defp xorin(dst, src, offset, len) do
    new = :crypto.exor(binary_part(src, offset, len), binary_part(dst, 0, len))
    dst2 = binary_put(dst, 0, new)
    {dst2, src}
  end

  defp setout(src, dst, offset, len) do
    new = binary_part(src, 0, len)
    dst2 = binary_put(dst, offset, new)
    {src, dst2}
  end

  # P*F over the full blocks of an input.
  defp foldP(a, inbin, len, fun, rate) when len >= rate do
    {a, inbin} = fun.(a, inbin, byte_size(inbin) - len, rate)
    a = keccakf(a)
    foldP(a, inbin, len - rate, fun, rate)
  end

  defp foldP(a, inbin, len, _fun, _rate) do
    {a, inbin, len}
  end

  defp binary_put(bin, offset, new) do
    binary_part(bin, 0, offset) <>
      new <> binary_part(bin, offset + byte_size(new), byte_size(bin) - (offset + byte_size(new)))
  end

  defp binary_new(size) do
    String.duplicate(<<0>>, size)
  end

  defp binary_xor(var, index, value) do
    index = floor(index)
    c = :crypto.exor(binary_part(var, index, 1), value)
    binary_put(var, index, c)
  end

  @plen 200
  defp hash(outlen, source, rate, delim) do
    outlen = floor(outlen)
    inlen = floor(byte_size(source))
    rate = floor(rate)

    # // Absorb input.
    a = binary_new(@plen)
    {a, _, inlen} = foldP(a, source, inlen, &xorin/4, rate)
    # // Xor source the DS and pad frame.
    a = binary_xor(a, inlen, <<delim>>)
    a = binary_xor(a, rate - 1, <<0x80>>)
    # // Xor source the last block.
    {a, _source} = xorin(a, source, floor(byte_size(source) - inlen), inlen)
    # // Apply P
    a = keccakf(a)
    # // Squeeze output.
    out = binary_new(outlen)
    {a, out, outlen} = foldP(a, out, outlen, &setout/4, rate)
    {_a, out} = setout(a, out, 0, outlen)
    out
  end

  defp keccak(bits, source), do: hash(bits / 8, source, 200 - bits / 4, 0x01)

  @doc """
   Keccak256 as in ethereum.Does not return 0x prefixed hex string.

  ## Examples

      iex> Keccak.keccak_256("hello")|>Base.encode16
      "1C8AFF950685C2ED4BC3174F3472287B56D9517B9C948127319A09A7A36DEAC8"

      iex> Keccak.keccak_256("hello")
      <<28, 138, 255, 149, 6, 133, 194, 237, 75, 195, 23, 79, 52, 114, 40, 123, 86,
       217, 81, 123, 156, 148, 129, 39, 49, 154, 9, 167, 163, 109, 234, 200>>
  """
  @spec keccak_256(binary()) :: binary()
  def keccak_256(source), do: keccak(256, source)
end
