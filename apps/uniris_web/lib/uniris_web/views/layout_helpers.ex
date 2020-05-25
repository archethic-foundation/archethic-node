defmodule UnirisWeb.LayoutHelpers do
    def format_date(%DateTime{ year: year, month: month, day: day, hour: hour, minute: minute, second: second}) do
        "#{year}/#{zero_pad(month)}/#{zero_pad(day)} #{zero_pad(hour)}:#{zero_pad(minute)}:#{zero_pad(second)}"
      end

      def format_date(nil), do: ""

      def zero_pad(number, amount \\ 2) do
        number
        |> Integer.to_string
        |> String.pad_leading(amount, "0")
      end
end
