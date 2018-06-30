defmodule Gitlab.Pagination do
  def all(base_option = %{}, func) do
    %{headers: headers, body: body} = func.(base_option)

    with {next, ""} <- Integer.parse(headers["X-Next-Page"]),
         {total, ""} <- Integer.parse(headers["X-Total-Pages"]) do
      next..total
      |> Enum.map(fn page_num ->
        func.(Map.merge(base_option, %{"page" => "#{page_num}"}))
      end)
      |> Enum.reduce(body, fn %{body: b}, acc -> [b | acc] end)
    else
      _ -> body
    end
  end
end
