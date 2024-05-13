defmodule Archethic.SharedSecrets.MemTables.NetworkLookup do
  @moduledoc false

  alias Archethic.Bootstrap.NetworkInit
  alias Archethic.Crypto

  use GenServer
  @vsn 2

  @table_name :archethic_shared_secrets_network

  @genesis_daily_nonce_public_key Application.compile_env!(:archethic, [
                                    NetworkInit,
                                    :genesis_daily_nonce_seed
                                  ])
                                  |> Crypto.generate_deterministic_keypair()
                                  |> elem(0)

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    :ets.new(@table_name, [:ordered_set, :named_table, :public, read_concurrency: true])
    :ets.insert(@table_name, {{:daily_nonce, 0}, @genesis_daily_nonce_public_key})

    {:ok, []}
  end

  @doc """
  Define a daily nonce public key at a given time

  ## Examples

      iex> NetworkLookup.start_link()
      ...> 
      ...> NetworkLookup.set_daily_nonce_public_key(
      ...>   <<0, 0, 57, 24, 251, 164, 133, 168, 109, 154, 9, 77, 197, 254, 138, 187, 250, 200, 37,
      ...>     115, 182, 174, 90, 206, 161, 228, 197, 77, 184, 101, 183, 164, 187, 96>>,
      ...>   ~U[2021-04-06 08:36:41Z]
      ...> )
      ...> 
      ...> NetworkLookup.set_daily_nonce_public_key(
      ...>   <<0, 0, 52, 242, 87, 194, 41, 203, 59, 163, 197, 116, 83, 28, 134, 140, 48, 74, 66, 21,
      ...>     248, 239, 162, 234, 35, 220, 113, 133, 73, 255, 58, 134, 225, 30>>,
      ...>   ~U[2021-04-07 08:36:41Z]
      ...> )
      ...> 
      ...> :ets.tab2list(:archethic_shared_secrets_network)
      [
        {{:daily_nonce, 0},
         <<0, 1, 207, 10, 216, 159, 45, 111, 246, 18, 53, 128, 31, 127, 69, 104, 136, 74, 244, 225,
           71, 122, 199, 230, 122, 233, 123, 61, 92, 150, 157, 139, 218, 8>>},
        {{:daily_nonce, 1_617_698_201},
         <<0, 0, 57, 24, 251, 164, 133, 168, 109, 154, 9, 77, 197, 254, 138, 187, 250, 200, 37, 115,
           182, 174, 90, 206, 161, 228, 197, 77, 184, 101, 183, 164, 187, 96>>},
        {{:daily_nonce, 1_617_784_601},
         <<0, 0, 52, 242, 87, 194, 41, 203, 59, 163, 197, 116, 83, 28, 134, 140, 48, 74, 66, 21,
           248, 239, 162, 234, 35, 220, 113, 133, 73, 255, 58, 134, 225, 30>>}
      ]
  """
  @spec set_daily_nonce_public_key(Crypto.key(), DateTime.t()) :: :ok
  def set_daily_nonce_public_key(public_key, date = %DateTime{}) when is_binary(public_key) do
    true = :ets.insert(@table_name, {{:daily_nonce, DateTime.to_unix(date)}, public_key})
    :ok
  end

  @doc """
  Retrieve the last daily nonce public key before current datetime

  ## Examples

      iex> NetworkLookup.start_link()
      ...> NetworkLookup.get_daily_nonce_public_key()
      <<0, 1, 207, 10, 216, 159, 45, 111, 246, 18, 53, 128, 31, 127, 69, 104, 136, 74, 244, 225, 71,
        122, 199, 230, 122, 233, 123, 61, 92, 150, 157, 139, 218, 8>>

      iex> NetworkLookup.start_link()
      ...> 
      ...> NetworkLookup.set_daily_nonce_public_key(
      ...>   <<0, 1, 57, 24, 251, 164, 133, 168, 109, 154, 9, 77, 197, 254, 138, 187, 250, 200, 37,
      ...>     115, 182, 174, 90, 206, 161, 228, 197, 77, 184, 101, 183, 164, 187, 96>>,
      ...>   ~U[2021-04-06 08:36:41Z]
      ...> )
      ...> 
      ...> NetworkLookup.set_daily_nonce_public_key(
      ...>   <<0, 1, 52, 242, 87, 194, 41, 203, 59, 163, 197, 116, 83, 28, 134, 140, 48, 74, 66, 21,
      ...>     248, 239, 162, 234, 35, 220, 113, 133, 73, 255, 58, 134, 225, 30>>,
      ...>   ~U[2021-04-07 08:36:41Z]
      ...> )
      ...> 
      ...> NetworkLookup.get_daily_nonce_public_key(~U[2021-04-07 10:00:00Z])
      <<0, 1, 52, 242, 87, 194, 41, 203, 59, 163, 197, 116, 83, 28, 134, 140, 48, 74, 66, 21, 248,
        239, 162, 234, 35, 220, 113, 133, 73, 255, 58, 134, 225, 30>>
      iex> NetworkLookup.get_daily_nonce_public_key(~U[2021-04-07 08:36:41Z])
      <<0, 1, 57, 24, 251, 164, 133, 168, 109, 154, 9, 77, 197, 254, 138, 187, 250, 200, 37, 115,
        182, 174, 90, 206, 161, 228, 197, 77, 184, 101, 183, 164, 187, 96>>
      iex> NetworkLookup.get_daily_nonce_public_key(~U[2021-04-07 00:00:00Z])
      <<0, 1, 57, 24, 251, 164, 133, 168, 109, 154, 9, 77, 197, 254, 138, 187, 250, 200, 37, 115,
        182, 174, 90, 206, 161, 228, 197, 77, 184, 101, 183, 164, 187, 96>>

  """
  @spec get_daily_nonce_public_key(DateTime.t()) :: Crypto.key()
  def get_daily_nonce_public_key(date \\ DateTime.utc_now()) do
    unix_time = DateTime.to_unix(date)

    [{_, public_key}] =
      case :ets.prev(@table_name, {:daily_nonce, unix_time}) do
        :"$end_of_table" ->
          :ets.lookup(@table_name, {:daily_nonce, unix_time})

        key ->
          :ets.lookup(@table_name, key)
      end

    public_key
  end

  def code_change(_, state, _extra), do: {:ok, state}
end
