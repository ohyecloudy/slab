defmodule Gitlab do
  require Logger
  use HTTPoison.Base

  def issue(id) do
    timeout = Keyword.get(Application.get_env(:slab, :gitlab), :timeout_ms)
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    access_token = Keyword.get(Application.get_env(:slab, :gitlab), :private_token)

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           HTTPoison.get(
             api_base_url <> "/issues/#{id}",
             ["Private-Token": "#{access_token}"],
             timeout: timeout
           ),
         {:ok, body} <- Poison.decode(body) do
      body
    else
      err ->
        Logger.info("#{inspect(err)}")
        %{}
    end
  end

  def issues(query_options = %{}) do
    timeout = Keyword.get(Application.get_env(:slab, :gitlab), :timeout_ms)
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    access_token = Keyword.get(Application.get_env(:slab, :gitlab), :private_token)
    url = api_base_url <> "/issues?" <> URI.encode_query(query_options)
    Logger.info("issues url - #{url}")

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           HTTPoison.get(
             url,
             ["Private-Token": "#{access_token}"],
             timeout: timeout
           ),
         {:ok, body} <- Poison.decode(body) do
      body
    else
      err ->
        Logger.info("#{inspect(err)}")
        []
    end
  end
end
