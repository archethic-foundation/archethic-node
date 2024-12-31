defmodule ArchethicWeb.API.JsonRPC.TransactionSchema do
  @moduledoc """
  Validate request parameter to match the transaction Json Schema
  """

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Utils

  @transaction_schema :archethic
                      |> Application.app_dir("priv/json-schemas/transaction.json")
                      |> File.read!()
                      |> Jason.decode!()
                      |> ExJsonSchema.Schema.resolve()

  @keys_to_base_decode [
    :address,
    :to,
    :token_address,
    :secret,
    :public_key,
    :encrypted_secret_key,
    :origin_signature,
    :previous_public_key,
    :previous_signature
  ]

  @doc """
  Validate a map to match the transaction Json Schema
  """
  @spec validate(params :: map()) :: :ok | {:error, map()} | :error
  def validate(params) when is_map(params) do
    with :ok <- ExJsonSchema.Validator.validate(@transaction_schema, params),
         :ok <- validate_contract_version(params),
         :ok <- validate_code_size(params),
         :ok <- validate_recipients_version(params) do
      :ok
    else
      {:error, reasons} -> {:error, format_errors(reasons)}
    end
  end

  def validate(_), do: :error

  defp validate_contract_version(%{"version" => version, "data" => %{"code" => code}})
       when code != "" and version >= 4,
       do: {:error, [{"From v4, code is deprecated", "#/data/code"}]}

  defp validate_contract_version(%{"version" => version, "data" => %{"contract" => contract}})
       when contract != nil and version <= 3,
       do: {:error, [{"Before V4, contract is not allowed", "#/data/contract"}]}

  defp validate_contract_version(_), do: :ok

  defp validate_code_size(%{"data" => %{"code" => code}})
       when is_binary(code) and code != "" do
    if TransactionData.code_size_valid?(code, false),
      do: :ok,
      else: {:error, [{"Invalid transaction, code exceed max size.", "#/data/code"}]}
  end

  defp validate_code_size(_), do: :ok

  defp validate_recipients_version(%{
         "version" => version,
         "data" => %{"recipients" => recipients}
       })
       when is_list(recipients) do
    cond do
      version == 1 and Enum.any?(recipients, &is_map/1) ->
        {:error, [{"Transaction V1 cannot use named action recipients", "#/data/recipients"}]}

      version >= 2 and Enum.any?(recipients, &is_binary/1) ->
        {:error, [{"From V2, transaction must use named action recipients", "#/data/recipients"}]}

      version >= 4 and Enum.any?(recipients, &is_list(Map.get(&1, "args"))) ->
        {:error, [{"From V4, recipient arguments must be a map", "#/data/recipients"}]}

      true ->
        :ok
    end
  end

  defp validate_recipients_version(_), do: :ok

  defp format_errors(errors),
    do: Enum.reduce(errors, %{}, fn {details, field}, acc -> Map.put(acc, field, details) end)

  @doc """
  Transform a map to a Transaction structure
  """
  @spec to_transaction(params :: map()) :: Transaction.t()
  def to_transaction(params) do
    # Remove recipient args to not convert them to atom
    {original_recipients, params} = remove_recipient_args(params)
    {origin_contract, params} = remove_contract(params)

    params
    |> Utils.atomize_keys(to_snake_case?: true)
    |> Utils.hex2bin(keys_to_base_decode: @keys_to_base_decode)
    |> format_ownerships()
    |> put_original_recipients_args(original_recipients)
    |> put_origin_contract(origin_contract)
    |> Transaction.cast()
  end

  defp remove_recipient_args(params) do
    get_and_update_in(params, ["data", "recipients"], fn
      nil ->
        {[], []}

      recipients ->
        updated_recipients =
          Enum.map(recipients, fn
            recipient = %{"args" => args} when is_list(args) -> Map.put(recipient, "args", [])
            recipient = %{"args" => args} when is_map(args) -> Map.put(recipient, "args", %{})
            recipient -> recipient
          end)

        {recipients, updated_recipients}
    end)
  end

  defp put_original_recipients_args(params, original_recipients) do
    update_in(params, [:data, :recipients], fn recipients ->
      recipients
      |> Enum.zip(original_recipients)
      |> Enum.map(fn
        {recipient = %{args: _}, original_recipient} ->
          Map.put(recipient, :args, Map.fetch!(original_recipient, "args"))

        {recipient, _} when is_binary(recipient) ->
          Base.decode16!(recipient, case: :mixed)

        {recipient, _} ->
          recipient
      end)
    end)
  end

  defp remove_contract(params) do
    get_and_update_in(params, ["data", "contract"], fn
      nil -> {nil, nil}
      contract -> {contract, nil}
    end)
  end

  defp put_origin_contract(params, nil), do: params

  defp put_origin_contract(params, %{"bytecode" => bytecode, "manifest" => manifest}) do
    update_in(params, [:data, :contract], fn _ ->
      %{bytecode: Base.decode16!(bytecode, case: :mixed), manifest: manifest}
    end)
  end

  defp format_ownerships(params) do
    update_in(params, [:data, :ownerships], fn
      nil -> []
      ownerships -> Enum.map(ownerships, &format_ownership/1)
    end)
  end

  defp format_ownership(ownership) do
    # Transform ownership's authorized_keys from list to map
    Map.update!(ownership, :authorized_keys, fn authorized_keys ->
      Enum.reduce(
        authorized_keys,
        %{},
        fn %{public_key: public_key, encrypted_secret_key: encrypted_secret_key}, acc ->
          Map.put(acc, public_key, encrypted_secret_key)
        end
      )
    end)
  end
end
