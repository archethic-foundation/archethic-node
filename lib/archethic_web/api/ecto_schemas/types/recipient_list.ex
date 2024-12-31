defmodule ArchethicWeb.API.Types.RecipientList do
  @moduledoc false

  use Ecto.Type

  alias Archethic.Crypto

  def type, do: :array

  def cast(recipients) when is_list(recipients) do
    results =
      Enum.map(recipients, fn
        address when is_binary(address) ->
          case validate_address(address) do
            {:ok, address_bin} -> address_bin
            err -> err
          end

        recipient = %{"address" => address} ->
          action = Map.get(recipient, "action")
          args = Map.get(recipient, "args")

          with {:ok, address_bin} <- validate_address(address),
               true <- valid_action_and_args?(action, args) do
            %{address: address_bin, action: action, args: args}
          else
            false -> {:error, "invalid recipient format"}
            err -> err
          end

        _ ->
          {:error, "invalid recipient format"}
      end)

    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] ->
        {:ok, results}

      errors ->
        {:error, Enum.map(errors, fn {:error, msg} -> {:message, msg} end)}
    end
  end

  def cast(_), do: {:error, [message: "must be an array"]}

  def load(recipients), do: recipients

  def dump(recipients) when is_list(recipients) do
    Enum.map(recipients, fn
      address when is_binary(address) -> Base.encode16(address)
      recipient = %{} -> Map.update!(recipient, :address, &Base.encode16/1)
    end)
  end

  def dump(_), do: :error

  defp validate_address(address) do
    with {:ok, address_bin} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(address_bin) do
      {:ok, address_bin}
    else
      :error -> {:error, "must be hexadecimal"}
      false -> {:error, "invalid hash"}
    end
  end

  defp valid_action_and_args?(_action = nil, _args = nil), do: true
  defp valid_action_and_args?(_action = "", _args), do: false

  defp valid_action_and_args?(action, args)
       when is_binary(action) and (is_list(args) or is_map(args)),
       do: true

  defp valid_action_and_args?(_, _), do: false
end
