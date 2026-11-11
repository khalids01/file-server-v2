defmodule AppWeb.PageControllerTest do
  use AppWeb.ConnCase

  test "GET /", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(html, "#landing-get-started") |> LazyHTML.to_tree() |> length() == 1
  end
end
