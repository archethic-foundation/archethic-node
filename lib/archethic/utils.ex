defmodule Archethic.Utils do
  @moduledoc false

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.P2P.Node

  alias Archethic.Reward.Scheduler, as: RewardScheduler

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionSummary

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  import Bitwise

  require Logger

  use Retry

  @extended_mode? Mix.env() != :prod

  @type bigint() :: integer()

  @doc """
  Convert a number to a bigint
  """
  @spec to_bigint(integer() | float()) :: bigint()
  def to_bigint(value) when is_integer(value) do
    value * 100_000_000
  end

  def to_bigint(value) when is_float(value) do
    value
    |> Decimal.from_float()
    |> Decimal.mult(100_000_000)
    |> Decimal.round(0, :floor)
    |> Decimal.to_integer()
  end

  @doc """
  Convert a bigint into a float
  """
  @spec from_bigint(bigint()) :: float()
  def from_bigint(value) do
    value
    |> Decimal.new()
    |> Decimal.div(100_000_000)
    |> Decimal.to_float()
  end

  @doc """
  Compute an offset of the next shift in seconds for a given time interval

  ## Examples

      # Time offset for the next 2 seconds
      iex> Utils.time_offset("*/2 * * * * *", ref_time: ~U[2020-09-24 20:13:12.10Z], time_unit: :millisecond)
      1900

      # Time offset for the next minute
      iex> Utils.time_offset("0 * * * * *", ref_time: ~U[2020-09-24 20:13:12.00Z])
      48000

      # Time offset for the next hour
      iex> Utils.time_offset("0 0 * * * *", ref_time: ~U[2020-09-24 20:13:00Z], time_unit: :second)
      2820

      # Time offset for the next day
      iex> Utils.time_offset("0 0 0 * * *", ref_time: ~U[2020-09-24 00:00:01Z], time_unit: :second)
      86399
  """
  @spec time_offset(cron_interval :: binary(), opts :: Keyword.t()) :: offset :: non_neg_integer()
  def time_offset(interval, opts \\ []) do
    ref_time = Keyword.get(opts, :ref_time, DateTime.utc_now())
    extended_mode = Keyword.get(opts, :extended_mode, true)
    time_unit = Keyword.get(opts, :time_unit, :millisecond)

    interval |> next_date(ref_time, extended_mode) |> DateTime.diff(ref_time, time_unit)
  end

  @doc """
  Return the closest interval tick before now
  """
  @spec get_current_time_for_interval(binary(), boolean()) :: DateTime.t()
  def get_current_time_for_interval(interval, extended_mode? \\ @extended_mode?) do
    rounded_now =
      if extended_mode? do
        DateTime.utc_now()
      else
        # if it's not extended we want to remove the seconds and micro seconds from the time.
        # we are adding 1 microsecond here because the previous_date function
        # would return the previous tick if we have the exact trigger time
        %DateTime{DateTime.utc_now() | second: 0, microsecond: {1, 0}}
      end

    interval
    |> CronParser.parse!(extended_mode?)
    |> previous_date(rounded_now)
  end

  @doc """
  Configure supervisor children to be disabled if their configuration has a `enabled` option to false
  """
  @spec configurable_children(
          list(
            (process ::
               any()
               | {process :: atom(), args :: list()}
               | {process :: atom(), args :: list(), opts :: list()})
            | %{id: atom(), start: {process :: atom(), fx :: atom(), args :: list(any())}}
            | Supervisor.child_spec()
          )
        ) ::
          list(Supervisor.child_spec())
  def configurable_children(children) when is_list(children) do
    children
    |> Enum.filter(fn
      %{start: {process, _, _}} -> should_start?(process)
      {process, _, _} -> should_start?(process)
      {process, _} -> should_start?(process)
      process -> should_start?(process)
    end)
    |> Enum.map(fn
      %{id: _, start: {_module, _method, _args}} = specs ->
        specs

      {process, args, opts} ->
        Supervisor.child_spec({process, args}, opts)

      {process, args} ->
        Supervisor.child_spec({process, args}, [])

      process ->
        Supervisor.child_spec({process, []}, [])
    end)
  end

  @spec should_start?(process :: atom() | nil) :: boolean()
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

      # iex> %{ "a" => "hello", "b.c" => "hi" } |> Utils.atomize_keys(nest_dot?: true)
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
      ...>       "token_address" => nil,
      ...>       "type" => "UCO"
      ...>     }
      ...>  ],
      ...>  "validation_stamp.signature" => <<48, 70, 2, 33, 0, 182, 126, 146, 243, 172,
      ...>    88, 55, 168, 10, 33, 112, 140, 182, 231, 143, 105, 61, 245, 34, 34, 171,
      ...>    221, 48, 165, 205, 196, 124, 240, 132, 54, 75, 237, 2, 33, 0, 141, 28, 71,
      ...>    218, 224, 201>>
      ...> }
      ...> |> Utils.atomize_keys(nest_dot?: true)
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
              token_address: nil
            }]
          },
          signature: <<48, 70, 2, 33, 0, 182, 126, 146, 243, 172,
            88, 55, 168, 10, 33, 112, 140, 182, 231, 143, 105, 61, 245, 34, 34, 171,
            221, 48, 165, 205, 196, 124, 240, 132, 54, 75, 237, 2, 33, 0, 141, 28, 71,
            218, 224, 201>>
        }
      }

      # iex> %{ "a.b.c" => "hello" } |> Utils.atomize_keys()
      # %{ "a.b.c": "hello"}

      # iex> %{ "argumentNames" => %{"firstName" => "toto"} } |> Utils.atomize_keys(to_snake_case?: true)
      # %{ :argument_names: %{firs_name: "toto"}}
  """
  @spec atomize_keys(map :: map(), opts :: Keyword.t()) :: map()
  def atomize_keys(map, opts \\ []) do
    nest_dot? = Keyword.get(opts, :nest_dot?, false)
    to_snake_case? = Keyword.get(opts, :to_snake_case?, false)

    atomize_keys(map, nest_dot?, to_snake_case?)
  end

  def atomize_keys(struct = %{__struct__: _}, _, _) do
    struct
  end

  def atomize_keys(map = %{}, nest_dot?, to_snake_case?) do
    map
    |> Enum.reduce(%{}, fn
      {k, v}, acc when is_binary(k) ->
        if String.valid?(k) do
          if nest_dot? and String.contains?(k, ".") do
            path =
              String.split(k, ".")
              |> Enum.map(fn k ->
                if to_snake_case?, do: Macro.underscore(k), else: k
              end)

            put_in(
              acc,
              nested_path(path),
              atomize_keys(v, nest_dot?, to_snake_case?)
            )
          else
            k = if to_snake_case?, do: Macro.underscore(k), else: k
            Map.put(acc, String.to_existing_atom(k), atomize_keys(v, nest_dot?, to_snake_case?))
          end
        else
          Map.put(acc, k, atomize_keys(v, nest_dot?, to_snake_case?))
        end

      {k, v}, acc ->
        Map.put(acc, k, atomize_keys(v, nest_dot?, to_snake_case?))
    end)
  end

  # Walk the list and atomize the keys of
  # of any map members
  def atomize_keys([head | []], nest_dot?, to_snake_case?),
    do: [atomize_keys(head, nest_dot?, to_snake_case?)]

  def atomize_keys([head | rest], nest_dot?, to_snake_case?) do
    [atomize_keys(head, nest_dot?, to_snake_case?)] ++
      atomize_keys(rest, nest_dot?, to_snake_case?)
  end

  def atomize_keys(not_a_map, _, _) do
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

  def deserialize_transaction_summaries(rest, 0, _acc), do: {[], rest}

  def deserialize_transaction_summaries(rest, nb_transaction_summaries, acc)
      when nb_transaction_summaries == length(acc),
      do: {Enum.reverse(acc), rest}

  def deserialize_transaction_summaries(rest, nb_transaction_summaries, acc) do
    {transaction_summary, rest} = TransactionSummary.deserialize(rest)
    deserialize_transaction_summaries(rest, nb_transaction_summaries, [transaction_summary | acc])
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

  @doc """
  Get the median value from a list.
  ## Examples
      iex> Utils.median([])
      nil
      iex> Utils.median([1,2,3])
      2
      iex> Utils.median([1,2,3,4])
      2.5
  """
  @spec median([number]) :: number | nil
  def median([]), do: nil
  ## To avoid all calculation from general clause to follow

  def median([number]), do: number
  ## To avoid all calculation from general clause to follow

  def median(numbers) do
    sorted = Enum.sort(numbers)
    length_list = length(sorted)

    case rem(length_list, 2) do
      1 -> Enum.at(sorted, div(length_list, 2))
      ## If we have an even number, media is the average of the two medium numbers
      0 -> Enum.slice(sorted, div(length_list, 2) - 1, 2) |> Enum.sum() |> Kernel./(2)
    end
  end

  @doc """
  Return the next date with the cron expression from a given date

  ## Examples

      iex> Utils.next_date("*/10 * * * * * *", ~U[2022-10-01 01:00:00Z])
      ~U[2022-10-01 01:00:10Z]

      iex> Utils.next_date("*/10 * * * * * *", ~U[2022-10-01 01:00:00.100Z])
      ~U[2022-10-01 01:00:10Z]

      iex> Utils.next_date("*/10 * * * * * *", ~U[2022-10-01 01:00:05Z])
      ~U[2022-10-01 01:00:10Z]

      iex> Utils.next_date("*/10 * * * * * *", ~U[2022-10-01 01:00:05.139Z])
      ~U[2022-10-01 01:00:10Z]
  """
  @spec next_date(interval :: binary(), date_from :: DateTime.t(), extended_mode? :: boolean()) ::
          next_date :: DateTime.t()
  def next_date(interval, date_from = %DateTime{}, extended_mode? \\ true) do
    cron_expression = CronParser.parse!(interval, extended_mode?)

    naive_date_from = DateTime.to_naive(date_from)

    if Crontab.DateChecker.matches_date?(cron_expression, naive_date_from) do
      case date_from do
        %DateTime{microsecond: {0, _}} ->
          cron_expression
          |> Crontab.Scheduler.get_next_run_dates(naive_date_from)
          |> Enum.at(1)
          |> DateTime.from_naive!("Etc/UTC")

        _ ->
          cron_expression
          |> Crontab.Scheduler.get_next_run_date!(naive_date_from)
          |> DateTime.from_naive!("Etc/UTC")
      end
    else
      cron_expression
      |> Crontab.Scheduler.get_next_run_date!(naive_date_from)
      |> DateTime.from_naive!("Etc/UTC")
    end
  end

  @doc """
  Return the previous date with the cron expression from a given date

  ## Examples

      iex> Utils.previous_date(%Crontab.CronExpression{second: [{:/, :*, 10}], extended: true}, ~U[2022-10-01 01:00:00Z])
      ~U[2022-10-01 00:59:50Z]

      iex> Utils.previous_date(%Crontab.CronExpression{second: [{:/, :*, 10}], extended: true}, ~U[2022-10-01 01:00:00.100Z])
      ~U[2022-10-01 01:00:00Z]

      iex> Utils.previous_date(%Crontab.CronExpression{second: [{:/, :*, 10}], extended: true}, ~U[2022-10-01 01:00:10Z])
      ~U[2022-10-01 01:00:00Z]

      iex> Utils.previous_date(%Crontab.CronExpression{second: [{:/, :*, 10}], extended: true}, ~U[2022-10-01 01:00:10.100Z])
      ~U[2022-10-01 01:00:10Z]

      iex> Utils.previous_date(%Crontab.CronExpression{second: [{:/, :*, 30}], extended: true}, ~U[2022-10-26 07:38:30.569648Z])
      ~U[2022-10-26 07:38:30Z]
  """
  @spec previous_date(Crontab.CronExpression.t(), DateTime.t()) :: DateTime.t()
  def previous_date(cron_expression, date_from = %DateTime{}) do
    naive_date_from = DateTime.to_naive(date_from)

    if Crontab.DateChecker.matches_date?(cron_expression, naive_date_from) do
      case date_from do
        %DateTime{microsecond: {microsecond, _}} when microsecond > 0 ->
          DateTime.truncate(date_from, :second)

        _ ->
          cron_expression
          |> Crontab.Scheduler.get_previous_run_dates(naive_date_from)
          |> Enum.at(1)
          |> DateTime.from_naive!("Etc/UTC")
      end
    else
      cron_expression
      |> Crontab.Scheduler.get_previous_run_date!(naive_date_from)
      |> DateTime.from_naive!("Etc/UTC")
    end
  end

  @doc """
  Return the number of occurences for the cron job over the month

  ## Examples

      iex> Utils.number_of_possible_reward_occurences_per_month_for_a_year("0 0 2 * * * *")
      %{
        0 => 31,
        1 => 30,
        2 => 29,
        3 => 28
      }
  """
  @spec number_of_possible_reward_occurences_per_month_for_a_year(String.t()) :: map
  def number_of_possible_reward_occurences_per_month_for_a_year(
        interval \\ Application.get_env(:archethic, RewardScheduler)[:interval]
      ) do
    months = [
      # 31 days
      ~N[2023-01-01 00:00:00.000000],
      # 30 days
      ~N[2023-04-01 00:00:00.000000],
      # 29 days
      ~N[2024-02-01 00:00:00.000000],
      # 28 days
      ~N[2023-02-01 00:00:00.000000]
    ]

    months
    |> Task.async_stream(
      fn date ->
        key = get_key_from_date(date)

        {key, number_of_reward_occurences_per_month(interval, date)}
      end,
      timeout: 10_000
    )
    |> Stream.map(fn {:ok, v} -> v end)
    |> Map.new()
  end

  @doc """
  Return the key for a given date

  ## Examples

      iex> Utils.get_key_from_date(~N[2023-01-01 00:00:00.000000])
      0

      iex> Utils.get_key_from_date(~N[2023-04-01 00:00:00.000000])
      1

      iex> Utils.get_key_from_date(~N[2023-02-01 00:00:00.000000])
      3

      iex> Utils.get_key_from_date(~N[2024-02-01 00:00:00.000000])
      2
  """
  def get_key_from_date(date) do
    # January March May July August October December have 31 days
    # April June September November have 30 days
    # February has 28 days or 29 days in a leap year
    case {Date.leap_year?(date), date.month} do
      {_, month} when month in [1, 3, 5, 7, 8, 10, 12] -> 0
      {_, month} when month in [4, 6, 9, 11] -> 1
      {true, 2} -> 2
      {false, 2} -> 3
    end
  end

  @doc """
  Return the number of occurences for the cron job over the month

  ## Examples

      iex> Utils.number_of_reward_occurences_per_month("0 0 2 * * * *", ~N[2022-11-01 00:00:00.000000])
      30

      iex> Utils.number_of_reward_occurences_per_month("0 0 2 * * * *", ~N[2022-12-01 00:00:00.000000])
      31

      iex> Utils.number_of_reward_occurences_per_month("0 0 2 * * * *", ~N[2022-02-01 00:00:00.000000])
      28

      iex> Utils.number_of_reward_occurences_per_month("0 0 2 * * * *", ~N[2024-02-01 00:00:00.000000])
      29
  """
  @spec number_of_reward_occurences_per_month(String.t(), NaiveDateTime.t()) :: non_neg_integer()
  def number_of_reward_occurences_per_month(interval, current_datetime) do
    time = fn
      true -> " 00:00:00Z"
      false -> " 23:59:59Z"
    end

    date_to_datetime_converter = fn date, start_of_month? ->
      time = time.(start_of_month?)

      NaiveDateTime.from_iso8601!("#{date}#{time}")
    end

    start_of_month_datetime =
      current_datetime
      |> Date.beginning_of_month()
      |> date_to_datetime_converter.(true)

    end_of_month_datetime =
      current_datetime
      |> Date.end_of_month()
      |> date_to_datetime_converter.(false)

    interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_dates(start_of_month_datetime)
    |> Stream.take_while(&(NaiveDateTime.compare(&1, end_of_month_datetime) in [:lt]))
    |> Enum.count()
  end

  @doc """
  get token properties based on the genesis address and the transaction
  """
  @spec get_token_properties(binary(), Transaction.t()) ::
          {:ok, map()} | {:error, :decode_error} | {:error, :not_a_token_transaction}
  def get_token_properties(genesis_address, %Transaction{
        data: %TransactionData{
          content: content,
          ownerships: ownerships
        },
        type: tx_type
      })
      when tx_type in [:token, :mint_rewards] do
    case Jason.decode(content) do
      {:ok, map} ->
        result = %{
          genesis: genesis_address,
          name: Map.get(map, "name", ""),
          supply: Map.get(map, "supply"),
          symbol: Map.get(map, "symbol", ""),
          type: Map.get(map, "type"),
          decimals: Map.get(map, "decimals", 8),
          properties: Map.get(map, "properties", %{}),
          collection: Map.get(map, "collection", []),
          ownerships: ownerships
        }

        token_id = get_token_id(genesis_address, result)

        {:ok, Map.put(result, :id, token_id)}

      _ ->
        {:error, :decode_error}
    end
  end

  def get_token_properties(_, _), do: {:error, :not_a_token_transaction}

  @doc """
  Run given function in a task and ensure that it is run at most once concurrently
  """
  def run_exclusive(key, fun) do
    registry = Archethic.RunExclusiveRegistry

    case Registry.lookup(registry, key) do
      [] ->
        Task.Supervisor.start_child(
          Archethic.TaskSupervisor,
          fn ->
            {:ok, _} = Registry.register(registry, key, nil)
            fun.(key)
          end
        )

      _ ->
        # there is already a concurrent run
        :ok
    end

    :ok
  end

  defp get_token_id(genesis_address, %{
         genesis: genesis_address,
         name: name,
         symbol: symbol,
         decimals: decimals,
         properties: properties
       }) do
    data_to_digest =
      %{
        genesis_address: Base.encode16(genesis_address),
        name: name,
        symbol: symbol,
        properties: properties,
        decimals: decimals
      }
      |> Jason.encode!()

    :crypto.hash(:sha256, data_to_digest)
    |> Base.encode16()
  end

  @doc """
  Return the standard deviation from a list

  ### Examples

      iex> Utils.standard_deviation([1, 2, 3, 4])
      1.118034
  """
  @spec standard_deviation(list()) :: number()
  def standard_deviation(list) do
    list_mean = mean(list)

    list
    |> Enum.map(fn x -> (list_mean - x) * (list_mean - x) end)
    |> mean()
    |> :math.sqrt()
    |> Float.round(6)
  end

  @doc """
  Return the mean from a list

  ### Examples

      iex> Utils.mean([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
      5.5
  """
  @spec mean(list()) :: number()
  def mean(list, t \\ 0, l \\ 0)
  def mean([], t, l), do: t / l

  def mean([x | xs], t, l) do
    mean(xs, t + x, l + 1)
  end

  @doc """
  Chunk a list into N sub lists

  ### Examples

      iex> Utils.chunk_list_in([1, 2, 3, 4, 5, 6], 3)
      [ [1, 2], [3, 4], [5, 6] ]

      iex> Utils.chunk_list_in([1, 2, 3, 4, 5, 6, 7], 3)
      [ [1, 2], [3, 4], [5, 6, 7] ]
  """
  @spec chunk_list_in(list(), pos_integer()) :: list(list())
  def chunk_list_in(list, parts) when is_list(list) and is_number(parts) and parts > 0 do
    list
    |> do_chunk(parts, [])
    |> Enum.reverse()
  end

  defp do_chunk(_, 0, chunks), do: chunks

  defp do_chunk(to_chunk, parts, chunks) do
    chunk_length = to_chunk |> length() |> div(parts)
    {chunk, rest} = Enum.split(to_chunk, chunk_length)
    do_chunk(rest, parts - 1, [chunk | chunks])
  end

  @spec await_confirmation(tx_address :: binary(), list(Node.t())) ::
          {:ok, Transaction.t()} | {:error, :network_issue}
  def await_confirmation(tx_address, nodes) do
    #  at 1th , 2th , 4th , 8th , 16th , 32th second
    retry_while with: exponential_backoff(1000, 2) |> expiry(70_000) do
      case TransactionChain.fetch_transaction(tx_address, nodes) do
        {:ok, transaction} ->
          {:halt, {:ok, transaction}}

        _ ->
          {:cont, {:error, :network_issue}}
      end
    end
  end

  @doc """
  Register a name to a supervisor
  """
  @spec register_supervisor_name(pid() | atom(), atom()) :: :ok | :not_found
  def register_supervisor_name(parent_supervisor, module_name) do
    case Supervisor.which_children(parent_supervisor)
         |> Enum.find(&(elem(&1, 0) == module_name)) do
      {_module, pid, _type, _param} when is_pid(pid) ->
        :erlang.register(module_name, pid)
        :ok

      _ ->
        :not_found
    end
  end

  @doc """
  Resolver function used by ExJsonSchema to resolve local path
  """
  @spec local_schema_resolver!(path :: binary()) :: map()
  def local_schema_resolver!("file://" <> path) do
    Application.app_dir(:archethic, "priv/json-schemas/#{path}")
    |> File.read!()
    |> Jason.decode!()
  end

  def local_schema_resolver!(_), do: raise("Invalid URI for $ref")
end
