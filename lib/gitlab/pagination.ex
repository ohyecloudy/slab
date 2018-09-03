defmodule Gitlab.Pagination do
  @spec all(map(), (map() -> %{headers: map(), body: [map()]})) :: [map()]
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

  @spec help_text(map(), map()) :: String.t()
  def help_text(headers, _original_query) when map_size(headers) == 0, do: ""

  def help_text(headers = %{}, original_query = %{}) do
    {total, _} = Integer.parse(headers["X-Total-Pages"])
    {cur, _} = Integer.parse(headers["X-Page"])

    prev =
      if cur > 1 do
        {_, suggest_option} =
          Map.get_and_update(original_query, "page", fn x ->
            {x, "#{cur - 1}"}
          end)

        "`#{inspect(suggest_option)}`, "
      else
        ""
      end

    next =
      if cur < total do
        {_, suggest_option} =
          Map.get_and_update(original_query, "page", fn x ->
            {x, "#{cur + 1}"}
          end)

        ", `#{inspect(suggest_option)}`"
      else
        ""
      end

    if total > 1 do
      prev <> "PAGE(#{cur}/#{total})" <> next
    else
      ""
    end
  end
end
