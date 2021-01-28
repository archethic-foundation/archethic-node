defmodule Uniris.Oracles.Coingecko do
  # curl -X GET "https://api.coingecko.com/api/v3/coins/uniris/history?date=20-01-2021" -H "accept: application/json"

  """
  {
    "id": "uniris",
    "symbol": "uco",
    "name": "Uniris",
    "localization": {
      "en": "Uniris",
      "de": "Uniris"
    },
    "image": {
      "thumb": "https://assets.coingecko.com/coins/images/12330/thumb/e353ZVj.png?1599112996",
      "small": "https://assets.coingecko.com/coins/images/12330/small/e353ZVj.png?1599112996"
    },
    "market_data": {
      "current_price": {
        "aed": 0.40477831668413594,
        "ars": 9.527034599711078
      },
      "market_cap": {
        "aed": 0,
        "ars": 0
      },
      "total_volume": {
        "aed": 290862.72072890576,
        "ars": 6845868.688941532
      }
    },
    "community_data": {
      "facebook_likes": null,
      "twitter_followers": 1749,
      "reddit_average_posts_48h": 0,
      "reddit_average_comments_48h": 0,
      "reddit_subscribers": 28,
      "reddit_accounts_active_48h": "4.61538461538461"
    },
    "developer_data": {
      "forks": null,
      "stars": null,
      "subscribers": null,
      "total_issues": null,
      "closed_issues": null,
      "pull_requests_merged": null,
      "pull_request_contributors": null,
      "code_additions_deletions_4_weeks": {
        "additions": null,
        "deletions": null
      },
      "commit_count_4_weeks": null
    },
    "public_interest_stats": {
      "alexa_rank": 1178558,
      "bing_matches": null
    }
  }
  """

  use HTTPoison.Base

  @endpoint "https://api.coingecko.com/api/v3/coins/uniris/history?date="

  def fetch(date) do
    "#{date.day}-#{date.month}-#{date.year}"
    |> get!
    |> Map.fetch!(:body)
  end

  defp process_request_url(date), do: @endpoint <> date

  defp process_response_body(body) do
    Jason.decode!(body)
    |> Map.fetch!("market_data")
    |> Map.fetch!("current_price")
    |> Jason.encode!
  end
end