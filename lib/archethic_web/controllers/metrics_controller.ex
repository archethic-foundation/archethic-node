defmodule ArchEthicWeb.MetricsController do
  alias TelemetryMetricsPrometheus.Core
  use ArchEthicWeb, :controller

  def index(conn, _params) do
    metrics = Core.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  @doc """
  checks whether the metrics data has labels(labels = tags)
  """
  def metrics_has_labes?(content) do
    [data_within_curly_brockets, _] = Regex.scan(~r/{(.*)}/, content) |> List.flatten()
    data_within_curly_brockets_length = String.split(data_within_curly_brockets, ",", trim: true)
    if Enum.count(data_within_curly_brockets_length) == 2, do: true, else: false
  end

  def parse_metrics_data_with_labels(content) do
    [{index_start_curl, _b} | _] = Regex.scan(~r/({)/, content, return: :index) |> List.flatten()
    [{index_equals, _b} | _] = Regex.scan(~r/(=)/, content, return: :index) |> List.flatten()
    [{index_le, _b} | _] = Regex.scan(~r/(le)/, content, return: :index) |> List.flatten()
    [{index_end_curl, _b} | _] = Regex.scan(~r/(})/, content, return: :index) |> List.flatten()

    distribution_name = String.slice(content, 0..(index_start_curl - 1)) |> String.to_atom()
    label = String.slice(content, (index_start_curl + 1)..(index_equals - 1)) |> String.to_atom()
    label_call = String.slice(content, (index_equals + 2)..(index_le - 3))
    bucket = String.slice(content, index_le..(index_le + 1)) |> String.to_atom()
    bucket_point = String.slice(content, (index_le + 4)..(index_end_curl - 2))
    bucket_result = :bucket_result
    bucket_total = String.slice(content, (index_end_curl + 2)..-1)

    bucket_map = %{label => label_call, bucket => bucket_point, bucket_result => bucket_total}
    Map.put_new(%{}, distribution_name, bucket_map)
  end

  def parse_metrics_sum_with_labels(content) do
    [{index_start_curl, _b} | _] = Regex.scan(~r/({)/, content, return: :index) |> List.flatten()
    [{index_equals, _b} | _] = Regex.scan(~r/(=)/, content, return: :index) |> List.flatten()
    [{index_end_curl, _b} | _] = Regex.scan(~r/(})/, content, return: :index) |> List.flatten()
    distribution_sum = String.slice(content, 0..(index_start_curl - 1)) |> String.to_atom()
    label = String.slice(content, (index_start_curl + 1)..(index_equals - 1)) |> String.to_atom()
    label_call = String.slice(content, (index_equals + 2)..(index_end_curl - 2))
    sum_result = :sum_result
    sum_total = String.slice(content, (index_end_curl + 2)..-1)

    sum_map = %{label => label_call, sum_result => sum_total}
    Map.put_new(%{}, distribution_sum, sum_map)
  end

  def parse_metrics_count_with_labels(content) do
    [{index_start_curl, _b} | _] = Regex.scan(~r/({)/, content, return: :index) |> List.flatten()
    [{index_equals, _b} | _] = Regex.scan(~r/(=)/, content, return: :index) |> List.flatten()
    [{index_end_curl, _b} | _] = Regex.scan(~r/(})/, content, return: :index) |> List.flatten()
    distribution_count = String.slice(content, 0..(index_start_curl - 1)) |> String.to_atom()
    label = String.slice(content, (index_start_curl + 1)..(index_equals - 1)) |> String.to_atom()
    label_call = String.slice(content, (index_equals + 2)..(index_end_curl - 2))
    count_result = :count_result
    count_total = String.slice(content, (index_end_curl + 2)..-1)

    count_map = %{label => label_call, count_result => count_total}
    Map.put_new(%{}, distribution_count, count_map)
  end

  def parse_metrics_data_without_labels(content) do
    [{index_start_curl, _b} | _] = Regex.scan(~r/({)/, content, return: :index) |> List.flatten()
    [{index_end_curl, _b} | _] = Regex.scan(~r/(})/, content, return: :index) |> List.flatten()
    distribution_name = String.slice(content, 0..(index_start_curl - 1)) |> String.to_atom()

    bucket =
      String.slice(content, (index_start_curl + 1)..(index_start_curl + 2)) |> String.to_atom()

    bucket_point = String.slice(content, (index_start_curl + 5)..(index_end_curl - 2))
    bucket_result = :bucket_result
    bucket_total = String.slice(content, (index_end_curl + 2)..-1)

    bucket_map = %{bucket => bucket_point, bucket_result => bucket_total}
    Map.put_new(%{}, distribution_name, bucket_map)
  end

  def parse_metrics_sum_without_labels(content) do
    [{index_sum, _b} | _] = Regex.scan(~r/(sum)/, content, return: :index) |> List.flatten()

    distribution_sum = String.slice(content, 0..(index_sum + 2)) |> String.to_atom()
    sum_result = :sum_result
    sum_total = String.slice(content, (index_sum + 4)..-1)

    sum_map = %{sum_result => sum_total}
    Map.put_new(%{}, distribution_sum, sum_map)
  end

  def parse_metrics_count_without_labels(content) do
    [{index_count, _b} | _] = Regex.scan(~r/(count)/, content, return: :index) |> List.flatten()

    distribution_count = String.slice(content, 0..(index_count + 4)) |> String.to_atom()
    count_result = :count_result
    count_total = String.slice(content, (index_count + 6)..-1)

    count_map = %{count_result => count_total}
    Map.put_new(%{}, distribution_count, count_map)
  end
end
