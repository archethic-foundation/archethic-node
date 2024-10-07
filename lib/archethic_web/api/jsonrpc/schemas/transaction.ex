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
    :previous_signature,
    :bytecode
  ]

  @doc """
  Validate a map to match the transaction Json Schema
  """
  @spec validate(params :: map()) :: :ok | {:error, map()} | :error
  def validate(params) when is_map(params) do
    with :ok <- ExJsonSchema.Validator.validate(@transaction_schema, params),
         :ok <- validate_code_size(params),
         :ok <- validate_code_manifest(params),
         :ok <- validate_recipients_version(params) do
      :ok
    else
      {:error, reasons} -> {:error, format_errors(reasons)}
    end
  end

  def validate(_), do: :error

  defp validate_code_size(params) do
    case get_in(params, ["data", "code"]) do
      nil ->
        :ok

      "" ->
        :ok

      code ->
        if TransactionData.code_size_valid?(code) do
          :ok
        else
          {:error,
           [
             {"Invalid transaction, code exceed max size.", "#/data/code"}
           ]}
        end
    end
  end

  defp validate_code_manifest(params) do
    case get_in(params, ["data", "contract"]) do
      nil ->
        :ok

      %{"manifest" => manifest} ->
        with {:ok, manifest_json} <- Jason.decode(manifest),
             :ok <- Archethic.Contracts.WasmSpec.validate_manifest(manifest_json) do
          :ok
        else
          {:error, %Jason.DecodeError{}} ->
            {:error, "Invalid transaction, contract manifest is not a valid json"}

          {:error, errors} ->
            {:error, format_errors(errors)}
        end
    end
  end

  defp validate_recipients_version(params = %{"version" => 1}) do
    case get_in(params, ["data", "recipients"]) do
      nil ->
        :ok

      recipients ->
        if Enum.any?(recipients, &is_map/1) do
          {:error, [{"Transaction V1 cannot use named action recipients", "#/data/recipients"}]}
        else
          :ok
        end
    end
  end

  defp validate_recipients_version(params = %{"version" => version}) do
    case get_in(params, ["data", "recipients"]) do
      nil ->
        :ok

      recipients ->
        if Enum.any?(recipients, &is_binary/1) do
          {:error,
           [{"From V2, transaction must use named action recipients", "#/data/recipients"}]}
        else
          if version > 3 and Enum.any?(recipients, &is_list(Map.get(&1, "args"))) do
            {:error, [{"From V4, recipient arguments must be a map", "#/data/recipients"}]}
          else
            :ok
          end
        end
    end
  end

  defp format_errors(errors),
    do: Enum.reduce(errors, %{}, fn {details, field}, acc -> Map.put(acc, field, details) end)

  @doc """
  Transform a map to a Transaction structure
  """
  @spec to_transaction(params :: map()) :: Transaction.t()
  def to_transaction(params) do
    # Remove recipient args to not convert them to atom
    {original_recipients, params} = remove_recipient_args(params)

    params
    |> Utils.atomize_keys(to_snake_case?: true)
    |> Utils.hex2bin(keys_to_base_decode: @keys_to_base_decode)
    |> format_ownerships()
    |> put_original_recipients_args(original_recipients)
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
