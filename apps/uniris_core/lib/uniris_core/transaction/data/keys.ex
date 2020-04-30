defmodule UnirisCore.TransactionData.Keys do
  defstruct authorized_keys: %{}, secret: ""

  alias UnirisCore.Crypto

  @type t :: %__MODULE__{
          secret: binary(),
          authorized_keys: %{(public_key :: Crypto.key()) => encrypted_key :: binary()}
        }

  @doc """
  Create a new transaction data keys

  ## Examples

      iex> secret_key = :crypto.strong_rand_bytes(32)
      iex> secret = "important message"
      iex> {pub, pv} = UnirisCore.Crypto.generate_deterministic_keypair("seed")
      iex> %{ authorized_keys: authorized_keys, secret: _} = UnirisCore.TransactionData.Keys.new([pub], secret_key, secret)
      iex> Map.keys(authorized_keys)
      [ <<0, 221, 228, 196, 111, 16, 222, 0, 119, 32, 150, 228, 25, 206, 79, 37, 213, 8, 130, 22, 212, 99, 55, 72, 11, 248, 250, 11, 140, 137, 167, 118, 253>> ]
  """
  @spec new(list(Crypto.key()), secret_key :: binary(), secret :: binary()) :: __MODULE__.t()
  def new(authorized_public_keys, secret_key, secret)
      when is_list(authorized_public_keys) and is_binary(secret_key) do
    Enum.reduce(authorized_public_keys, %__MODULE__{secret: secret}, fn public_key, acc = %{} ->
      encrypted_secret_key = Crypto.ec_encrypt(secret_key, public_key)
      Map.update!(acc, :authorized_keys, &Map.put(&1, public_key, encrypted_secret_key))
    end)
  end
end
