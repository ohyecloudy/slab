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

    get(url)
  end

  def commit(id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/repository/commits/#{id}"

    %{body: body} = get(url, %{})
    body
  end

  def commits(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/repository/commits?" <> URI.encode_query(query_options)

    get(url)
  end

  def protected_branches_access_level(level) do
    # https://docs.gitlab.com/ee/api/protected_branches.html 참고
    Map.get(%{"no" => 0, "developer" => 30, "maintainer" => 40, "admin" => 60}, level, nil)
  end

  def protected_branches(attrs = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)

    with branch_name when not is_nil(branch_name) <- Map.get(attrs, :name),
         :ok <- delete(api_base_url <> "/protected_branches/#{branch_name}") do
      url = api_base_url <> "/protected_branches?" <> URI.encode_query(attrs)
      post(url)
    end
  end

  def merge_request(id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/merge_requests/#{id}"

    %{body: body} = get(url)
    body
  end

  def merge_requests(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/merge_requests?" <> URI.encode_query(query_options)

    get(url)
  end

  def merge_requests_associated_with(commit_id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/repository/commits/#{commit_id}/merge_requests"

    get(url)
  end

  def pipelines(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/pipelines?" <> URI.encode_query(query_options)

    get(url)
  end

  def pipeline(id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/pipelines/#{id}"

    %{body: body} = get(url)
    body
  end

  def pipeline_status(branch) do
    %{body: pipelines} = Gitlab.pipelines(%{"per_page" => "100", "ref" => branch})

    pipelines
    |> Stream.map(fn %{"id" => id} -> Gitlab.pipeline(id) end)
    |> pipelines_custom_filter
    |> take_until_last_suceess
    |> build_pipeline_status
    |> Map.put(:branch, branch)
  end

  defp get(url, default_body \\ []) do
    timeout = Keyword.get(Application.get_env(:slab, :gitlab), :timeout_ms)
    access_token = Keyword.get(Application.get_env(:slab, :gitlab), :private_token)

    Logger.info("GET - #{url}")

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
        Logger.warn("#{inspect(err)}")
        %{headers: %{}, body: default_body}
    end
  end

  defp post(url) do
    timeout = Keyword.get(Application.get_env(:slab, :gitlab), :timeout_ms)
    access_token = Keyword.get(Application.get_env(:slab, :gitlab), :private_token)

    Logger.info("POST - #{url}")

    with {:ok, %HTTPoison.Response{status_code: status_code, headers: headers, body: body}} <-
           HTTPoison.post(
             url,
             "",
             ["Private-Token": "#{access_token}"],
             timeout: timeout
           ),
         true <- status_code >= 200,
         {:ok, body} <- Poison.decode(body) do
      %{headers: Map.new(headers), body: body}
    else
      err ->
        Logger.warn("#{inspect(err)}")
        %{headers: %{}, body: %{}}
    end
  end

  defp delete(url) do
    timeout = Keyword.get(Application.get_env(:slab, :gitlab), :timeout_ms)
    access_token = Keyword.get(Application.get_env(:slab, :gitlab), :private_token)

    Logger.info("DELETE - #{url}")

    with {:ok, %HTTPoison.Response{status_code: status_code}} <-
           HTTPoison.delete(
             url,
             ["Private-Token": "#{access_token}"],
             timeout: timeout
           ),
         true <- status_code >= 200 do
      :ok
    else
      err ->
        Logger.warn("#{inspect(err)}")
        err
    end
  end

  defp pipelines_custom_filter(pipelines) do
    filter = Application.get_env(:slab, :pipeline_custom_filter)

    if filter do
      Logger.info("process custom pipelines filter - #{inspect(filter)}")
      Stream.filter(pipelines, filter)
    else
      pipelines
    end
  end

  defp take_until_last_suceess(pipelines) do
    idx = Enum.find_index(pipelines, fn %{"status" => status} -> status == "success" end)

    if idx do
      Enum.take(pipelines, idx + 1)
    else
      Enum.take(pipelines, 0)
    end
  end

  defp build_pipeline_status(pipelines) do
    success = List.last(pipelines)
    failed = Enum.find(pipelines, fn %{"status" => status} -> status == "failed" end)
    running = Enum.find(pipelines, fn %{"status" => status} -> status == "running" end)

    %{
      success: pipeline_commit(success),
      failed: pipeline_commit(failed),
      running: pipeline_commit(running)
    }
  end

  defp pipeline_commit(nil), do: nil

  defp pipeline_commit(pipeline) do
    %{pipeline: pipeline, commit: Gitlab.commit(pipeline["sha"])}
  end
end
