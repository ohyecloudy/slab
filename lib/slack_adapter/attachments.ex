defmodule SlackAdapter.Attachments do
  @spec from_issues([map()], :summary) :: [map()]
  def from_issues(issues, :summary) do
    Enum.map(issues, fn x = %{} ->
      %{
        color: "#939393",
        title: "\##{x["iid"]} #{x["title"]}",
        title_link: "#{x["web_url"]}"
      }
    end)
  end

  @spec from_issue(map(), :detail) :: [map()] | []
  def from_issue(issue, :detail) when map_size(issue) == 0, do: []

  def from_issue(issue = %{}, :detail) do
    author =
      if issue["assignee"] == nil do
        %{author_name: "담당자 없음"}
      else
        %{
          author_name: issue["assignee"]["name"],
          author_icon: issue["assignee"]["avatar_url"],
          author_link: issue["assignee"]["web_url"]
        }
      end

    issue_state =
      case issue["state"] do
        "closed" -> " (closed)"
        _ -> ""
      end

    [
      Map.merge(
        %{
          fallback: "#{issue["title"]}",
          color: "#939393",
          title: "\##{issue["iid"]} #{issue["title"]}#{issue_state}",
          title_link: "#{issue["web_url"]}"
        },
        author
      )
    ]
  end

  @spec from_commits([map()], :summary) :: [map()]
  def from_commits(commits, :summary) do
    base_url = Keyword.get(Application.get_env(:slab, :gitlab), :url) <> "/commit"

    Enum.map(commits, fn x = %{} ->
      %{
        color: "#939393",
        title: "#{x["short_id"]} [#{x["author_name"]}] #{x["title"]}",
        title_link: "#{base_url}/#{x["id"]}"
      }
    end)
  end

  @spec from_merge_request_with_issues(map) :: [map]
  def from_merge_request_with_issues(%{mr: mr, issues: issues}) do
    author =
      if mr["author"] == nil do
        %{author_name: "작성자 없음"}
      else
        %{
          author_name: mr["author"]["name"],
          author_icon: mr["author"]["avatar_url"],
          author_link: mr["author"]["web_url"]
        }
      end

    [
      Map.merge(
        %{
          color: "#939393",
          title: "#{mr["target_branch"]} <- #{mr["title"]}",
          title_link: mr["web_url"]
        },
        author
      ),
      issues
    ] ++
      from_issues(issues, :summary)
  end

  @spec from_merge_requests([map()]) :: [map()]
  def from_merge_requests(mrs) do
    mrs
    |> Enum.map(fn x = %{} ->
      author = get_in(x, ["author", "name"])
      assignee = get_in(x, ["assignee", "name"])
      merged_by = get_in(x, ["merged_by", "name"])

      %{
        color: "#939393",
        title:
          "[#{inspect(author)} -> #{inspect(assignee)}, MERGED_BY #{inspect(merged_by)}] #{
            x["title"]
          }",
        title_link: x["web_url"]
      }
    end)
  end

  @spec from_protected_branches(map()) :: [map()] | []
  def from_protected_branches(branches) do
    with name when not is_nil(name) <- Map.get(branches, "name"),
         merge_levels when merge_levels != [] <- Map.get(branches, "merge_access_levels", []),
         push_levels when push_levels != [] <- Map.get(branches, "push_access_levels", []) do
      merge_levels =
        merge_levels
        |> Enum.map(&Map.get(&1, "access_level_description"))
        |> Enum.join(",")

      push_levels =
        push_levels
        |> Enum.map(&Map.get(&1, "access_level_description"))
        |> Enum.join(",")

      [
        %{
          color: "#7CD197",
          pretext: ":tada: *#{name}* 브랜치 access level 설정 성공 :tada:",
          fields: [
            %{
              title: "merge 권한",
              value: merge_levels,
              short: true
            },
            %{
              title: "push 권한",
              value: push_levels,
              short: true
            }
          ]
        }
      ]
    else
      _ -> []
    end
  end

  def limit_count, do: 20

  @spec from_pipelines(map()) :: [map()]
  def from_pipelines(%{success: success, failed: failed, running: running, branch: branch}) do
    a_success = pipeline_common_attachment(success)
    a_failed = pipeline_common_attachment(failed)
    a_running = pipeline_common_attachment(running)

    summary =
      cond do
        success && failed ->
          """
          :boom: `#{branch}` 브랜치 빌드
          :mag: 커밋 조회 - `git log --oneline --graph #{String.slice(success.pipeline["sha"], 0..10)}..#{
            String.slice(failed.pipeline["sha"], 0..10)
          }`
          """

        success ->
          ":tada: `#{branch}` 브랜치 빌드는 그린라이트"

        true ->
          ""
      end

    [%{pretext: summary}, a_success, a_failed, a_running]
  end

  @spec pipeline_common_attachment(nil | map()) :: map()
  defp pipeline_common_attachment(nil), do: %{}

  defp pipeline_common_attachment(%{pipeline: pipeline, commit: commit}) do
    base_url = Keyword.get(Application.get_env(:slab, :gitlab), :url) <> "/pipelines"

    commit_author =
      commit
      |> get_in(["author_name"])
      |> case do
        nil -> ""
        author -> ", author(#{author})"
      end

    {status_title, color} =
      case pipeline["status"] do
        "success" -> {"성공한 파이프라인", "#7CD197"}
        "failed" -> {"실패한 파이프라인", "#F35A00"}
        "running" -> {"실행 중 파이프라인", "#0099f3"}
        _ -> {"", "#939393"}
      end

    %{
      color: "#{color}",
      title: "#{status_title} - #{pipeline["id"]}#{commit_author}",
      title_link: "#{base_url}/#{pipeline["id"]}"
    }
  end
end
