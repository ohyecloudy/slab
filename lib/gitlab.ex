defmodule Gitlab do
  require Logger
  use HTTPoison.Base

  def issue(id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/issues/#{id}"

    %{body: body} = get(url, %{})
    body
  end

  def issues(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/issues?" <> URI.encode_query(query_options)
    Logger.info("issues url - #{url}")

    get(url)
  end

  def commits(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/repository/commits?" <> URI.encode_query(query_options)
    Logger.info("commits url - #{url}")

    get(url)
  end

  def merge_requests(commit_id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/repository/commits/#{commit_id}/merge_requests"
    Logger.info("merge requests url - #{url}")

    get(url)
  end

  defp get(url, default_body \\ []) do
    timeout = Keyword.get(Application.get_env(:slab, :gitlab), :timeout_ms)
    access_token = Keyword.get(Application.get_env(:slab, :gitlab), :private_token)

    with {:ok, %HTTPoison.Response{status_code: 200, headers: headers, body: body}} <-
           HTTPoison.get(
             url,
             ["Private-Token": "#{access_token}"],
             timeout: timeout
           ),
         {:ok, body} <- Poison.decode(body) do
      %{headers: Map.new(headers), body: body}
    else
      err ->
        Logger.info("#{inspect(err)}")
        %{headers: %{}, body: default_body}
    end
  end
end
