defmodule AppWeb.UI.UserMenuTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  defp menu(attrs) do
    user =
      Map.merge(
        %{name: "Khalid", email: "k@example.com", operator: false, avatar_url: nil},
        attrs
      )

    render_component(&AppWeb.UI.UserMenu.user_menu/1, user: user) |> LazyHTML.from_fragment()
  end

  test "GitHub avatar renders, with optional admin entry" do
    doc = menu(%{avatar_url: "https://avatars.githubusercontent.com/u/123", operator: true})

    assert [_] =
             LazyHTML.query(
               doc,
               "#user-menu-button img[src='https://avatars.githubusercontent.com/u/123']"
             )
             |> LazyHTML.to_tree()

    assert [_] = LazyHTML.query(doc, "a[href='/dashboard/admin']") |> LazyHTML.to_tree()
  end

  test "name initial falls back to email and rejects non-GitHub image sources" do
    doc = menu(%{name: "  Émilie ", avatar_url: "javascript:alert(1)"})
    assert LazyHTML.query(doc, "#user-menu-button span") |> LazyHTML.text() == "É"
    assert [] = LazyHTML.query(doc, "img, a[href='/dashboard/admin']") |> LazyHTML.to_tree()

    assert menu(%{name: nil}) |> LazyHTML.query("#user-menu-button span") |> LazyHTML.text() ==
             "K"
  end
end
