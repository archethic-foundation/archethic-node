defmodule UnirisCrypto.SoftwareImpl.Keystore do
  @moduledoc false
  use Agent

  alias UnirisCrypto.SoftwareImpl, as: Impl
  alias UnirisCrypto.SoftwareImpl.ECDSA
  alias UnirisCrypto.SoftwareImpl.Ed25519
  alias UnirisCrypto.ID

  @sources [:node, :origin, :shared]
  @labels [:first, :last, :previous]

  def start_link(opts) do
    seed = Keyword.get(opts, :seed)
    {origin_pub, origin_pv} = Keyword.get(opts, :origin_keypair)

    extended_seed = Impl.get_extended_seed(seed, 0)

    default_curve = Application.get_env(:uniris_crypto, :default_curve)

    with {:ok, curve_id} <- ID.get_id_from_curve(default_curve) do
      {pub, pv} =
        case default_curve do
          :ed25519 ->
            with {:ok, pub, pv} <- Ed25519.generate_keypair(extended_seed) do
              {pub, pv}
            end

          curve ->
            ECDSA.generate_keypair(extended_seed, curve)
        end

      Agent.start_link(
        fn ->
          %{
            seed: seed,
            origin: %{
              first: %{
                public_key: origin_pub,
                private_key: origin_pv
              },
              last: %{
                public_key: origin_pub,
                private_key: origin_pv
              }
            },
            node: %{
              first: %{
                public_key: <<curve_id::8>> <> pub,
                private_key: <<curve_id::8>> <> pv
              },
              last: %{
                public_key: <<curve_id::8>> <> pub,
                private_key: <<curve_id::8>> <> pv
              },
              previous: %{
                public_key: <<curve_id::8>> <> pub,
                private_key: <<curve_id::8>> <> pv
              }
            },
            shared: %{
              first: %{},
              last: %{}
            }
          }
        end,
        name: __MODULE__
      )
    end
  end

  @spec get_seed() :: binary()
  def get_seed(), do: Agent.get(__MODULE__, & &1.seed)

  @spec set_keypair(:node | :origin | :shared, binary(), binary()) :: :ok
  def set_keypair(label, pub, pv)
      when label in @sources and is_binary(pub) and is_binary(pv) do
    Agent.update(__MODULE__, fn s ->
      keypair = %{
        public_key: pub,
        private_key: pv
      }

      case get_in(s, [label, :first]) do
        %{public_key: _, private_key: _} = first ->
          case get_in(s, [label, :last]) do
            %{public_key: _, private_key: _} = previous ->
              s
              |> put_in([label, :previous], previous)
              |> put_in([label, :last], keypair)

            %{} ->
              s
              |> put_in([label, :last], keypair)
              |> put_in([label, :previous], first)
          end

        %{} ->
          s
          |> put_in([label, :first], keypair)
          |> put_in([label, :last], keypair)
      end
    end)
  end

  @spec get_private_key(:node | :origin | :shared, :first | :last | :previous) ::
          {:ok, binary()} | {:error, :missing_key}
  def get_private_key(source, label)
      when source in @sources and label in @labels do
    Agent.get(__MODULE__, fn s ->
      case get_in(s, [source, label]) do
        %{private_key: private_key} ->
          {:ok, private_key}

        %{} ->
          {:error, :missing_key}
      end
    end)
  end

  @spec get_public_key(:node | :origin | :shared, :first | :last | :previous) ::
          {:ok, binary()} | {:error, :missing_key}
  def get_public_key(source, label)
      when source in [:node, :origin, :shared] and label in [:first, :last, :previous] do
    Agent.get(__MODULE__, fn s ->
      case get_in(s, [source, label]) do
        %{public_key: public_key} ->
          {:ok, public_key}

        %{} ->
          {:error, :missing_key}
      end
    end)
  end
end
