defmodule Gitlab do
  require Logger
  use HTTPoison.Base

  def issue(id) do
    timeout = Keyword.get(Application.get_env(:gitlab_straw, :gitlab), :timeout_ms)
    api_base_url = Keyword.get(Application.get_env(:gitlab_straw, :gitlab), :api_base_url)
    access_token = Keyword.get(Application.get_env(:gitlab_straw, :gitlab), :private_token)

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
end
