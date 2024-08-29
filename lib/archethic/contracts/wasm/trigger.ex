defmodule Archethic.Contracts.WasmTrigger do
  @moduledoc false
  @type t :: %__MODULE__{
          function_name: String.t(),
          type: :transaction | {:datetime, DateTime.t()} | {:interval, String.t()} | :oracle
        }
  defstruct [:function_name, :type]

  def cast({function_name, %{"type" => 0}}),
    do: %__MODULE__{type: :transaction, function_name: function_name}

  def cast({function_name, %{"type" => 1, "argument" => datetime_timestamp}}),
    do: %__MODULE__{
      type: {:datetime, DateTime.from_unix!(String.to_integer(datetime_timestamp))},
      function_name: function_name
    }

  def cast({function_name, %{"type" => 2, "argument" => crontab}}),
    do: %__MODULE__{type: {:interval, crontab}, function_name: function_name}

  def cast({function_name, %{"type" => 3}}),
    do: %__MODULE__{type: :oracle, function_name: function_name}
end
