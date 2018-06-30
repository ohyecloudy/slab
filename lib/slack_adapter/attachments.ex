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
