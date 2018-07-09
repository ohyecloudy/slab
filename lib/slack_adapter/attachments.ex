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
         merge_levels when length(merge_levels) > 0 <-
           Map.get(branches, "merge_access_levels", []),
         push_levels when length(push_levels) > 0 <- Map.get(branches, "push_access_levels", []) do
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
end
