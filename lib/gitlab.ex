defmodule Gitlab do
  require Logger
  use HTTPoison.Base

  @type list_response :: %{headers: map(), body: [map()]}

  @spec issue(pos_integer()) :: map()
  def issue(id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/issues/#{id}"

    %{body: body} = get(url, %{})
    body
  end

  @spec issues(map()) :: list_response()
  def issues(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/issues?" <> URI.encode_query(query_options)

    get(url)
  end

  @spec commit(pos_integer()) :: map()
  def commit(id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/repository/commits/#{id}"

    %{body: body} = get(url, %{})
    body
  end

  @spec commits(map()) :: list_response()
  def commits(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/repository/commits?" <> URI.encode_query(query_options)

    get(url)
  end

  @spec protected_branches_access_level(String.t()) :: non_neg_integer() | nil
  def protected_branches_access_level(level) do
    # https://docs.gitlab.com/ee/api/protected_branches.html 참고
    Map.get(%{"no" => 0, "developer" => 30, "maintainer" => 40, "admin" => 60}, level, nil)
  end

  @spec protected_branches(map()) :: %{headers: map(), body: map()} | atom()
  def protected_branches(attrs = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)

    with branch_name when not is_nil(branch_name) <- Map.get(attrs, :name),
         :ok <- delete(api_base_url <> "/protected_branches/#{branch_name}") do
      url = api_base_url <> "/protected_branches?" <> URI.encode_query(attrs)
      post(url)
    else
      _ -> :error
    end
  end

  @spec merge_request(pos_integer()) :: map()
  def merge_request(id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/merge_requests/#{id}"

    %{body: body} = get(url)
    body
  end

  @spec merge_requests(map()) :: list_response()
  def merge_requests(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/merge_requests?" <> URI.encode_query(query_options)

    get(url)
  end

  @spec merge_requests_associated_with(pos_integer()) :: list_response()
  def merge_requests_associated_with(commit_id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/repository/commits/#{commit_id}/merge_requests"

    get(url)
  end

  @spec pipelines(map()) :: list_response()
  def pipelines(query_options = %{}) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/pipelines?" <> URI.encode_query(query_options)

    get(url)
  end

  @spec pipeline(pos_integer()) :: map()
  def pipeline(id) do
    api_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :api_base_url)
    url = api_base_url <> "/pipelines/#{id}"

    %{body: body} = get(url)
    body
  end

  @spec pipeline_status(String.t()) :: %{
          success: map() | nil,
          failed: map() | nil,
          running: map() | nil,
          branch: String.t()
        }
  def pipeline_status(branch) do
    Gitlab.PaginationStream.create(&Gitlab.pipelines/1, %{"ref" => branch})
    |> Stream.map(fn %{"id" => id} -> Gitlab.pipeline(id) end)
    |> pipelines_custom_filter
    |> take_until_last_suceess
    |> build_pipeline_status
    |> Map.put(:branch, branch)
  end

  @spec get(String.t(), any()) :: %{headers: map(), body: any()}
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

  @spec post(String.t()) :: %{headers: map(), body: any()}
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

  @spec delete(String.t()) :: any()
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

  @spec pipelines_custom_filter(Enumerable.t()) :: Enumerable.t()
  defp pipelines_custom_filter(pipelines) do
    filter = Application.get_env(:slab, :pipeline_custom_filter)

    if filter do
      Logger.info("process custom pipelines filter - #{inspect(filter)}")
      Stream.filter(pipelines, filter)
    else
      pipelines
    end
  end

  @spec take_until_last_suceess(Enumerable.t()) :: Enumerable.t()
  defp take_until_last_suceess(pipelines) do
    pipelines
    |> Stream.transform(false, fn i, found_success ->
      if found_success do
        {:halt, found_success}
      else
        {[i], i["status"] == "success"}
      end
    end)
    |> Enum.to_list()
  end

  @spec build_pipeline_status(Enumerable.t()) :: %{
          success: map() | nil,
          failed: map() | nil,
          running: map() | nil
        }
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

  @spec pipeline_commit(map() | nil) :: map() | nil
  defp pipeline_commit(nil), do: nil

  defp pipeline_commit(pipeline) do
    %{pipeline: pipeline, commit: Gitlab.commit(pipeline["sha"])}
  end
end
