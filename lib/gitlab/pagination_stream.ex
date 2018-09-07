defmodule Gitlab.PaginationStream do
  require Logger

  @per_page "100"

  @spec create((map() -> %{headers: map(), body: [any()]}), map()) :: Enumerable.t()
  def create(fun, param) do
    Stream.resource(
      fn ->
        param = Map.merge(param, %{"per_page" => @per_page, "page" => "1"})
        %{headers: headers, body: body} = fun.(param)

        with {total, ""} <- Integer.parse(headers["X-Total-Pages"]) do
          {1, total, body}
        else
          _ -> {1, 1, body}
        end
      end,
      fn
        {current, total, body} ->
          {body, {current + 1, total}}

        {current, total} ->
          if current > total do
            {:halt, {current, total}}
          else
            param = Map.merge(param, %{"per_page" => @per_page, "page" => "#{current}"})
            %{body: body} = fun.(param)
            {body, {current + 1, total}}
          end
      end,
      fn {_current, _total} -> :ok end
    )
  end
end
