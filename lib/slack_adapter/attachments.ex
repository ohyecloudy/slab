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
end
