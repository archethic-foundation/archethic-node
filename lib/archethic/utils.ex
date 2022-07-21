defmodule Archethic.Utils do
  @moduledoc false

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.P2P.Node

  import Bitwise

  @doc """
  Compute an offset of the next shift in seconds for a given time interval

  ## Examples

      # Time offset for the next 2 seconds
      iex> Utils.time_offset("*/2 * * * * *", ~U[2020-09-24 20:13:12.10Z])
      2
      # 12 seconds + offset == 14 seconds

      # Time offset for the next minute
      iex> Utils.time_offset("0 * * * * *", ~U[2020-09-24 20:13:12.00Z])
      48
      # 12 seconds + offset == 60 seconds (1 minute)

      # Time offset for the next hour
      iex> Utils.time_offset("0 0 * * * *", ~U[2020-09-24 20:13:00Z])
      2820
      # 13 minutes: 720 seconds + offset == 3600 seconds (one hour)

      # Time offset for the next day
      iex> Utils.time_offset("0 0 0 * * *", ~U[2020-09-24 00:00:01Z])
      86399
      # 1 second + offset = 86400 (1 day)
  """
  @spec time_offset(cron_interval :: binary()) :: seconds :: non_neg_integer()
  def time_offset(interval, ref_time \\ DateTime.utc_now()) do
    next_slot =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_next_run_date!(DateTime.to_naive(ref_time))
      |> DateTime.from_naive!("Etc/UTC")

    DateTime.diff(next_slot, ref_time, :second)
  end

  @doc """
  Configure supervisor children to be disabled if their configuration has a `enabled` option to false
  """
  @spec configurable_children(
          list(
            process ::
              atom()
              | {process :: atom(), args :: list()}
              | {process :: atom(), args :: list(), opts :: list()}
          )
        ) ::
          list(Supervisor.child_spec())
  def configurable_children(children) when is_list(children) do
    children
    |> Enum.filter(fn
      {process, _, _} -> should_start?(process)
      {process, _} -> should_start?(process)
      process -> should_start?(process)
    end)
    |> Enum.map(fn
      {process, args, opts} -> Supervisor.child_spec({process, args}, opts)
      {process, args} -> Supervisor.child_spec({process, args}, [])
      process -> Supervisor.child_spec({process, []}, [])
    end)
  end

  defp should_start?(nil), do: false

  defp should_start?(process) do
    case Application.get_env(:archethic, process) do
      nil ->
        true

      conf when is_list(conf) ->
        Keyword.get(conf, :enabled, true)

      mod when is_atom(mod) ->
        :archethic
        |> Application.get_env(mod, [])
        |> Keyword.get(:enabled, true)
    end
  end

  @doc """
  Truncate a datetime to remove either second or microsecond

  ## Examples

      iex> Utils.truncate_datetime(~U[2021-02-08 16:52:37.542918Z])
      ~U[2021-02-08 16:52:37Z]

      iex> Utils.truncate_datetime(~U[2021-02-08 16:52:37.542918Z], second?: true, microsecond?: true)
      ~U[2021-02-08 16:52:00Z]

      iex> Utils.truncate_datetime(~U[2021-02-08 16:52:37.542918Z], second?: true)
      ~U[2021-02-08 16:52:00.542918Z]
  """
  def truncate_datetime(date = %DateTime{}, opts \\ [second?: false, microsecond?: true]) do
    Enum.reduce(opts, date, fn opt, acc ->
      case opt do
        {:second?, true} ->
          %{acc | second: 0}

        {:microsecond?, true} ->
          %{acc | microsecond: {0, 0}}

        _ ->
          acc
      end
    end)
  end

  @doc """
  Convert map string keys to :atom keys

  ## Examples

      # iex> %{ "a" => "hello", "b" => "hola", "c" => %{"d" => "hi"}} |> Utils.atomize_keys()
      # %{
      #   a: "hello",
      #   b: "hola",
      #   c: %{
      #     d: "hi"
      #   }
      # }

      # iex> %{ "a" => "hello", "b.c" => "hi" } |> Utils.atomize_keys(true)
      # %{
      #   a: "hello",
      #   b: %{
      #     c: "hi"
      #   }
      # }

      iex> %{
      ...>  "address" => <<0, 177, 211, 117, 14, 219, 147, 129, 201, 107, 26, 151, 90, 85,
      ...>    181, 180, 228, 251, 55, 191, 171, 16, 76, 16, 176, 182, 201, 160, 4, 51,
      ...>    236, 70, 70>>,
      ...>  "type" => "transfer",
      ...>  "validation_stamp.ledger_operations.unspent_outputs" => [
      ...>     %{
      ...>       "amount" => 9.989999771118164,
      ...>       "from" => <<0, 177, 211, 117, 14, 219, 147, 129, 201, 107, 26, 151, 90,
      ...>         85, 181, 180, 228, 251, 55, 191, 171, 16, 76, 16, 176, 182, 201, 160, 4,
      ...>         51, 236, 70, 70>>,
      ...>       "nft_address" => nil,
      ...>       "type" => "UCO"
      ...>     }
      ...>  ],
      ...>  "validation_stamp.signature" => <<48, 70, 2, 33, 0, 182, 126, 146, 243, 172,
      ...>    88, 55, 168, 10, 33, 112, 140, 182, 231, 143, 105, 61, 245, 34, 34, 171,
      ...>    221, 48, 165, 205, 196, 124, 240, 132, 54, 75, 237, 2, 33, 0, 141, 28, 71,
      ...>    218, 224, 201>>
      ...> }
      ...> |> Utils.atomize_keys(true)
      %{
        address: <<0, 177, 211, 117, 14, 219, 147, 129, 201, 107, 26, 151, 90, 85, 181, 180, 228, 251,
                    55, 191, 171, 16, 76, 16, 176, 182, 201, 160, 4, 51, 236, 70, 70>>,
        type: "transfer",
        validation_stamp: %{
          ledger_operations: %{
            unspent_outputs: [%{
              amount: 9.989999771118164,
              from: <<0, 177, 211, 117, 14, 219, 147, 129, 201, 107, 26, 151, 90,
                85, 181, 180, 228, 251, 55, 191, 171, 16, 76, 16, 176, 182, 201, 160, 4,
                51, 236, 70, 70>>,
              type: "UCO",
              nft_address: nil
            }]
          },
          signature: <<48, 70, 2, 33, 0, 182, 126, 146, 243, 172,
            88, 55, 168, 10, 33, 112, 140, 182, 231, 143, 105, 61, 245, 34, 34, 171,
            221, 48, 165, 205, 196, 124, 240, 132, 54, 75, 237, 2, 33, 0, 141, 28, 71,
            218, 224, 201>>
        }
      }

      # iex> %{ "a.b.c" => "hello" } |> Utils.atomize_keys(false)
      # %{ "a.b.c": "hello"}
  """
  @spec atomize_keys(map(), nest_dot? :: boolean()) :: map()
  def atomize_keys(map, nest_dot? \\ false)

  def atomize_keys(struct = %{__struct__: _}, _nest_dot?) do
    struct
  end

  def atomize_keys(map = %{}, nest_dot?) do
    map
    |> Enum.reduce(%{}, fn
      {k, v}, acc when is_binary(k) ->
        if String.valid?(k) do
          if nest_dot? and String.contains?(k, ".") do
            put_in(acc, nested_path(String.split(k, ".")), atomize_keys(v, nest_dot?))
          else
            Map.put(acc, String.to_existing_atom(k), atomize_keys(v, nest_dot?))
          end
        else
          Map.put(acc, k, atomize_keys(v, nest_dot?))
        end

      {k, v}, acc ->
        Map.put(acc, k, atomize_keys(v, nest_dot?))
    end)
  end

  # Walk the list and atomize the keys of
  # of any map members
  def atomize_keys([head | []], _), do: [atomize_keys(head)]

  def atomize_keys([head | rest], _) do
    [atomize_keys(head)] ++ atomize_keys(rest)
  end

  def atomize_keys(not_a_map, _) do
    not_a_map
  end

  defp nested_path(_keys, acc \\ [])

  defp nested_path([key | []], acc) do
    Enum.reverse([Access.key(String.to_existing_atom(key)) | acc])
  end

  defp nested_path([key | rest], acc) do
    nested_path(rest, [Access.key(String.to_existing_atom(key), %{}) | acc])
  end

  @doc """
  Convert map atom keys to strings

  ## Examples

      iex> %{ a: "hello", b: "hola", c: %{d: "hi"}} |> Utils.stringify_keys()
      %{
        "a" => "hello",
        "b" => "hola",
        "c" => %{
          "d" => "hi"
        }
      }
  """
  @spec stringify_keys(map()) :: map()
  def stringify_keys(struct = %{__struct__: _}) do
    struct
  end

  def stringify_keys(map = %{}) do
    map
    |> Enum.map(fn {k, v} ->
      {to_string(k), stringify_keys(v)}
    end)
    |> Enum.into(%{})
  end

  # Walk the list and stringify the keys of
  # of any map members
  def stringify_keys([head | []]), do: [stringify_keys(head)]

  def stringify_keys([head | rest]) do
    [stringify_keys(head)] ++ stringify_keys(rest)
  end

  def stringify_keys(not_a_map) do
    not_a_map
  end

  @doc """
  Determines if the public key if inside the node list

  ## Examples

      iex> Utils.key_in_node_list?([%Node{first_public_key: "key1", last_public_key: "key2"}], "key1")
      true

      iex> Utils.key_in_node_list?([%Node{first_public_key: "key1", last_public_key: "key2"}], "key2")
      true
  """
  @spec key_in_node_list?(list(Node.t()), Crypto.key()) :: boolean()
  def key_in_node_list?(nodes, public_key) when is_list(nodes) and is_binary(public_key) do
    Enum.any?(nodes, &(&1.first_public_key == public_key or &1.last_public_key == public_key))
  end

  @doc """
  Wrap any bitstring which is not byte even by padding the remaining bits to make an even binary

  ## Examples

      iex> Utils.wrap_binary(<<1::1>>)
      <<1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>

      iex> Utils.wrap_binary(<<33, 50, 10>>)
      <<33, 50, 10>>

      iex> Utils.wrap_binary([<<1::1, 1::1, 1::1>>, "hello"])
      [<<1::1, 1::1, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1>>, "hello"]

      iex> Utils.wrap_binary([[<<1::1, 1::1, 1::1>>, "abc"], "hello"])
      [ [<<1::1, 1::1, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1>>, "abc"], "hello"]
  """
  @spec wrap_binary(iodata() | bitstring() | list(bitstring())) :: binary()
  def wrap_binary(bits) when is_binary(bits), do: bits

  def wrap_binary(bits) when is_bitstring(bits) do
    size = bit_size(bits)

    if rem(size, 8) == 0 do
      bits
    else
      # Find out the next greater multiple of 8
      round_up = Bitwise.band(size + 7, -8)
      pad_bitstring(bits, round_up - size)
    end
  end

  def wrap_binary(data, acc \\ [])

  def wrap_binary([data | rest], acc) when is_list(data) do
    iolist =
      data
      |> Enum.reduce([], &[wrap_binary(&1) | &2])
      |> Enum.reverse()

    wrap_binary(rest, [iolist | acc])
  end

  def wrap_binary([data | rest], acc) when is_bitstring(data) do
    wrap_binary(rest, [wrap_binary(data) | acc])
  end

  def wrap_binary([], acc), do: Enum.reverse(acc)

  defp pad_bitstring(original_bits, additional_bits) do
    <<original_bits::bitstring, 0::size(additional_bits)>>
  end

  # @doc """
  # Unwrap a bitstring padded

  # ## Examples

  #     # Bitstring wrapped and padded as <<128>> binary
  #     iex> Utils.unwrap_bitstring(<<1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>, 2)
  #     {<<1::1, 0::1>>, ""}

  #     # Bitstring wrapped and padded as <<208>> binary
  #     iex> Utils.unwrap_bitstring(<<1::1, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1, 0::1>>, 4)
  #     {<<1::1, 1::1, 0::1, 1::1>>, ""}

  #     # Bitstring wrapped and padded as <<208, 1, 2, 3>> binary
  #     iex> Utils.unwrap_bitstring(<<1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 1, 2, 3>>, 4)
  #     {<<1::1, 0::1, 0::1, 0::1>>, <<1, 2, 3>>}
  # """
  # def unwrap_bitstring("", 0), do: {<<>>, <<>>}

  # def unwrap_bitstring(bitstring, data_size)
  #     when is_bitstring(bitstring) and is_integer(data_size) and data_size > 0 do
  #   wrapped_bitstring_size = Bitwise.band(data_size + 7, -8)
  #   padding_bitstring_size = abs(data_size - wrapped_bitstring_size)

  #   <<data_bitstring::bitstring-size(data_size), _::bitstring-size(padding_bitstring_size),
  #     rest::bitstring>> = bitstring

  #   {data_bitstring, rest}
  # end

  @doc """
  Take a elements in map recursively from a list of fields to fetch

  ## Examples

     iex> Utils.take_in(%{a: "hello", b: %{c: "hi", d: "hola"}}, [])
     %{a: "hello", b: %{c: "hi", d: "hola"}}

     iex> Utils.take_in(%{a: "hello", b: %{c: "hi", d: "hola"}}, [:a, b: [:d]])
     %{a: "hello", b: %{d: "hola"}}
  """
  @spec take_in(map(), Keyword.t()) :: map()
  def take_in(map = %{}, []), do: map

  def take_in(map = %{}, fields) when is_list(fields) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      case v do
        %{} ->
          Map.put(acc, k, take_in(v, Keyword.get(fields, k, [])))

        _ ->
          do_take_in(acc, map, k, fields)
      end
    end)
  end

  defp do_take_in(acc, map, key, fields) do
    if key in fields do
      Map.put(acc, key, Map.get(map, key))
    else
      acc
    end
  end

  @doc """
  Aggregate two sequences of bits using an OR bitwise operation

  ## Examples

      iex> Utils.aggregate_bitstring(<<1::1, 0::1, 1::1, 1::1>>, <<0::1, 1::1, 1::1, 0::1>>)
      <<1::1, 1::1, 1::1, 1::1>>

      iex> Utils.aggregate_bitstring(<<1::1, 0::1, 1::1, 1::1>>, <<0::1, 0::1, 1::1>>)
      <<1::1, 0::1, 1::1, 1::1>>
  """
  @spec aggregate_bitstring(bitstring(), bitstring()) :: bitstring()
  def aggregate_bitstring(seq1, seq2)
      when is_bitstring(seq1) and is_bitstring(seq2) and bit_size(seq1) == bit_size(seq2) do
    do_aggregate(seq1, seq2, 0)
  end

  def aggregate_bitstring(seq1, seq2)
      when is_bitstring(seq1) and is_bitstring(seq2) and bit_size(seq1) != bit_size(seq2),
      do: seq1

  defp do_aggregate(seq1, _, index) when bit_size(seq1) == index do
    seq1
  end

  defp do_aggregate(seq1, seq2, index) do
    <<prefix_seq1::size(index), bit_seq1::size(1), rest_seq1::bitstring>> = seq1
    <<_::size(index), bit_seq2::size(1), _::bitstring>> = seq2

    new_seq1 = <<prefix_seq1::size(index), bit_seq1 ||| bit_seq2::size(1), rest_seq1::bitstring>>

    do_aggregate(new_seq1, seq2, index + 1)
  end

  @doc """
  Represents a bitstring in a list of 0 and 1

  ## Examples

      iex> Utils.bitstring_to_integer_list(<<1::1, 1::1, 0::1>>)
      [1, 1, 0]
  """
  @spec bitstring_to_integer_list(bitstring()) :: list()
  def bitstring_to_integer_list(sequence) when is_bitstring(sequence) do
    bitstring_to_list(sequence, [])
  end

  defp bitstring_to_list(<<b::size(1), bits::bitstring>>, acc) do
    bitstring_to_list(bits, [b | acc])
  end

  defp bitstring_to_list(<<>>, acc), do: acc |> Enum.reverse()

  @doc """
  Set bit in a sequence at a given position

  ## Examples

      iex> Utils.set_bitstring_bit(<<0::1, 0::1, 0::1>>, 1)
      <<0::1, 1::1, 0::1>>
  """
  @spec set_bitstring_bit(bitstring(), non_neg_integer()) :: bitstring()
  def set_bitstring_bit(seq, pos)
      when is_bitstring(seq) and is_integer(pos) and pos >= 0 and bit_size(seq) > pos do
    <<prefix::size(pos), _::size(1), suffix::bitstring>> = seq
    <<prefix::size(pos), 1::size(1), suffix::bitstring>>
  end

  @doc """
  Count the number of bits set in the bitstring

  ## Examples

      iex> Utils.count_bitstring_bits(<<1::1, 0::1, 1::1, 0::1>>)
      2
  """
  @spec count_bitstring_bits(bitstring()) :: non_neg_integer()
  def count_bitstring_bits(bitstring) when is_bitstring(bitstring),
    do: do_count_bits(bitstring, 0)

  defp do_count_bits(<<1::1, rest::bitstring>>, acc), do: do_count_bits(rest, acc + 1)
  defp do_count_bits(<<0::1, rest::bitstring>>, acc), do: do_count_bits(rest, acc)
  defp do_count_bits(<<>>, acc), do: acc

  @doc """
  Convert datetime to a human readable time
  """
  @spec time_to_string(DateTime.t()) :: binary()
  def time_to_string(time = %DateTime{}) do
    time
    |> truncate_datetime()
    |> DateTime.to_string()
  end

  @spec get_keys_from_value_match(Keyword.t(), any()) :: list(atom())
  def get_keys_from_value_match(list, value) when is_list(list) do
    Enum.reduce(list, [], fn
      {key, ^value}, acc ->
        [key | acc]

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  def impl(mod) do
    :archethic
    |> Application.get_env(mod)
    |> Keyword.fetch!(:impl)
  end

  @doc """
  Returns path in the mutable storage directory
  """
  @spec mut_dir(String.t() | nonempty_list(Path.t())) :: Path.t()
  def mut_dir(path) when is_binary(path) do
    [
      get_root_mut_dir(),
      Application.get_env(:archethic, :mut_dir),
      path
    ]
    |> Path.join()
    |> Path.expand()
  end

  def mut_dir(path = [_]) when is_list(path) do
    [
      get_root_mut_dir(),
      Application.get_env(:archethic, :mut_dir) | path
    ]
    |> Path.join()
    |> Path.expand()
  end

  def mut_dir, do: mut_dir("")

  defp get_root_mut_dir() do
    case Application.get_env(:archethic, :root_mut_dir) do
      nil -> Application.app_dir(:archethic)
      dir -> dir
    end
  end

  @doc """
  Return the remaining seconds from timer
  """
  @spec remaining_seconds_from_timer(reference()) :: non_neg_integer()
  def remaining_seconds_from_timer(timer) when is_reference(timer) do
    case Process.read_timer(timer) do
      false ->
        0

      milliseconds ->
        div(milliseconds, 1000)
    end
  end

  @doc """
  Clear the mailbox of the current process
  """
  @spec flush_mailbox() :: :ok
  def flush_mailbox do
    receive do
      _ ->
        flush_mailbox()
    after
      0 ->
        :ok
    end
  end

  def deserialize_address(<<curve_type::8, hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<hash::binary-size(hash_size), rest::bitstring>> = rest
    {<<curve_type::8, hash_id::8, hash::binary>>, rest}
  end

  def deserialize_addresses(rest, 0, _), do: {[], rest}

  def deserialize_addresses(rest, nb_addresses, acc) when length(acc) == nb_addresses do
    {Enum.reverse(acc), rest}
  end

  def deserialize_addresses(rest, nb_addresses, acc) do
    {address, rest} = deserialize_address(rest)
    deserialize_addresses(rest, nb_addresses, [address | acc])
  end

  def deserialize_hash(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<hash::binary-size(hash_size), rest::bitstring>> = rest
    {<<hash_id::8, hash::binary>>, rest}
  end

  def deserialize_public_key(<<curve_id::8, origin_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)
    <<public_key::binary-size(key_size), rest::bitstring>> = rest
    {<<curve_id::8, origin_id::8, public_key::binary>>, rest}
  end

  def deserialize_public_key_list(rest, 0, _acc), do: {[], rest}

  def deserialize_public_key_list(rest, nb_keys, acc) when length(acc) == nb_keys do
    {Enum.reverse(acc), rest}
  end

  def deserialize_public_key_list(rest, nb_keys, acc) do
    {public_key, rest} = deserialize_public_key(rest)
    deserialize_public_key_list(rest, nb_keys, [public_key | acc])
  end

  def deserialize_transaction_attestations(rest, 0, _acc), do: {[], rest}

  def deserialize_transaction_attestations(rest, nb_attestations, acc)
      when nb_attestations == length(acc),
      do: {Enum.reverse(acc), rest}

  def deserialize_transaction_attestations(rest, nb_attestations, acc) do
    {attestation, rest} = ReplicationAttestation.deserialize(rest)
    deserialize_transaction_attestations(rest, nb_attestations, [attestation | acc])
  end

  @doc """
  Convert the seconds to human readable format

  ## Examples

      iex> Archethic.Utils.seconds_to_human_readable(3666)
      "1 hour 01 minute 06 second"

      iex> Archethic.Utils.seconds_to_human_readable(66)
      "1 minute 06 second"

      iex> Archethic.Utils.seconds_to_human_readable(6)
      "0 minute 06 second"
  """
  def seconds_to_human_readable(0), do: "00:00:00"

  def seconds_to_human_readable(seconds) do
    seconds = round(seconds)
    units = [3600, 60, 1]

    [h | t] =
      Enum.map_reduce(units, seconds, fn unit, val -> {div(val, unit), rem(val, unit)} end)
      |> elem(0)
      |> Enum.drop_while(&match?(0, &1))

    {h, t} = if t == [], do: {0, [h]}, else: {h, t}

    base_unit = if length(t) > 1, do: "hour", else: "minute"

    "#{h} #{base_unit} #{t |> Enum.map_join(" minute ", fn term -> term |> Integer.to_string() |> String.pad_leading(2, "0") end)} second"
  end

  @doc """
  Converts a list of map to a Single Map.

  ## Examples

      iex> [%{k: 5}, %{m: 5}, %{v: 3}]
      ...> |>Utils.merge_list_of_maps()
      %{k: 5, m: 5, v: 3}

  """
  def merge_list_of_maps(list_of_map) do
    Enum.reduce(list_of_map, _acc = %{}, fn a, acc ->
      Map.merge(a, acc, fn _key, a1, a2 ->
        a1 + a2
      end)
    end)
  end
end
