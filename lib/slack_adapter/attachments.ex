defmodule SlackAdapter.Attachments do
  def from_issues(issues, :summary) when is_list(issues) do
    Enum.map(issues, fn x = %{} ->
      %{
        color: "#939393",
        title: "\##{x["iid"]} #{x["title"]}",
        title_link: "#{x["web_url"]}"
      }
    end)
  end

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

    [
      Map.merge(
        %{
          fallback: "#{issue["title"]}",
          color: "#939393",
          title: "\##{issue["iid"]} #{issue["title"]}",
          title_link: "#{issue["web_url"]}",
          text: "#{String.slice(issue["description"], 0..100)}",
          fields: [
            %{
              title: "labels",
              value: Enum.join(issue["labels"], ","),
              short: false
            }
          ],
          footer: "slab"
        },
        author
      )
    ]
  end

  def from_commits(commits, :summary) when is_list(commits) do
    base_url = Keyword.get(Application.get_env(:slab, :gitlab), :url) <> "/commit"

    Enum.map(commits, fn x = %{} ->
      %{
        color: "#939393",
        title: "#{x["short_id"]} [#{x["author_name"]}] #{x["title"]}",
        title_link: "#{base_url}/#{x["id"]}"
      }
    end)
  end

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
    end
  end

  def limit_count, do: 20

  def from_pipelines(%{success: success, failed: failed, running: running, branch: branch}) do
    a_success = pipeline_common_attachment(success)
    a_failed = pipeline_common_attachment(failed)
    a_running = pipeline_common_attachment(running)

    summary =
      cond do
        success && failed ->
          """
          :boom: `#{branch}` 브랜치 빌드가 깨져있습니다. 확인 해주세요. :boom:

          `git log --oneline --graph #{String.slice(success.pipeline["sha"], 0..10)}..#{
            String.slice(failed.pipeline["sha"], 0..10)
          }` 명령으로 빌드에 영향을 준 커밋을 조회할 수 있습니다.
          """

        success ->
          ":tada: `#{branch}` 브랜치 빌드는 그린라이트 :tada:"

        true ->
          ""
      end

    [%{pretext: summary}, a_success, a_failed, a_running]
  end

  defp pipeline_common_attachment(nil), do: %{}

  defp pipeline_common_attachment(%{pipeline: pipeline, commit: commit}) do
    base_url = Keyword.get(Application.get_env(:slab, :gitlab), :url) <> "/pipelines"

    pipeline_info =
      with finished when not is_nil(finished) <- pipeline["finished_at"],
           {:ok, datetime, _} <- DateTime.from_iso8601(finished) do
        finished_at =
          datetime
          |> Timex.Timezone.convert(Timex.Timezone.local())
          |> DateTime.to_string()

        %{
          title: "pipeline finished",
          value: finished_at,
          short: true
        }
      else
        _ -> nil
      end

    commit_info =
      if commit do
        %{
          fields: [
            %{
              title: "commit id",
              value: "#{String.slice(pipeline["sha"], 0..10)}",
              short: true
            },
            %{
              title: "commit title",
              value: commit["title"],
              short: true
            },
            %{
              title: "commit author",
              value: commit["author_name"],
              short: true
            }
          ]
        }
      else
        %{
          fields: [
            %{
              title: "commit id",
              value: "#{String.slice(pipeline["sha"], 0..10)}",
              short: true
            }
          ]
        }
      end

    fields =
      if pipeline_info do
        Map.update!(commit_info, :fields, fn old -> old ++ [pipeline_info] end)
      else
        commit_info
      end

    {status_title, color} =
      case pipeline["status"] do
        "success" -> {"성공한 파이프라인", "#7CD197"}
        "failed" -> {"실패한 파이프라인", "#F35A00"}
        "running" -> {"실행 중 파이프라인", "#0099f3"}
        _ -> {"", "#939393"}
      end

    Map.merge(fields, %{
      color: "#{color}",
      title: "#{status_title} - #{pipeline["id"]}",
      title_link: "#{base_url}/#{pipeline["id"]}"
    })
  end
end
