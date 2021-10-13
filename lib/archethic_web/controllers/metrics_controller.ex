defmodule ArchEthicWeb.MetricsController do
  alias TelemetryMetricsPrometheus.Core
  use ArchEthicWeb, :controller

  def index(conn, _params) do
    metrics = Core.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  def parse_help(content) do
    [_, _, name] = Regex.run(~r/(.*\s)(.*)/, content)
    %{"help" => name}
    # Jason.encode!(map)
  end

  def parse_type(content) do
    [_, _, _, type] = Regex.run(~r/(.*\s)(.*\s)(.*)/, content)
    %{"type" => type}
    # Jason.encode!(map)
  end

  def parse_with_curly(content) do
    [_, _metric_name, lab, value] = Regex.run(~r/(.*){(.*)}(.*)/, content)
    [bucket, label, handler] = data_within_curl(lab)
    bucket_val = %{bucket => value |> remove_string(~r/ /, "")}
    buckets = %{"buckets" => bucket_val}
    labels = %{"labels" => %{"method" => label, "handler" => handler}}
    {:ok, buckets, labels}
  end

  def parse_with_curly_no_label(content) do
    [_, _metric_name, lab, value] = Regex.run(~r/(.*){(.*)}(.*)/, content)
    [bucket] = data_within_curl(lab)
    bucket_val = %{bucket => value |> remove_string(~r/ /, "")}
    %{"buckets" => bucket_val}
  end

  def parse_sum_count_with_label(content) do
    [_, name, _lab, value] = Regex.run(~r/_(sum|count){(.*)}(.*)/, content)
    %{name => value |> remove_string(~r/ /, "")}
  end

  def parse_sum_count_no_label_no_curly(content) do
    [_, name, value] = Regex.run(~r/_(sum|count)(.*)/, content)
    %{name => value |> remove_string(~r/ /, "")}
  end

  defp data_within_curl(labels) do
    labels
    |> remove_string(~r/"/)
    |> String.split(",")
    |> Enum.reduce([], fn match, acc ->
      [key, val] = String.split(match, "=")
      [key | [val | acc]] |> Enum.reject(fn le -> le == "le" end)
    end)
  end

  def remove_string(str, regex, replacement \\ "") do
    Regex.replace(regex, str, replacement)
  end

  def check_for_help?(content), do: String.match?(content, ~r/HELP/)
  def check_for_type?(content), do: String.match?(content, ~r/TYPE/)
  def check_for_curly?(content), do: String.match?(content, ~r/{|}/)
  def check_for_no_curly?(content), do: !String.match?(content, ~r/{|}|(HELP)|(TYPE)/)
  def check_for_sum_count_with_curly?(content), do: String.match?(content, ~r/_sum{|_count{/)
  def check_for_le_with_curly?(content), do: String.match?(content, ~r/le/)
end
