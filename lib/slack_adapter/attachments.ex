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

  def limit_count, do: 20
end
