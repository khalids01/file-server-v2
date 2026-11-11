defmodule AppWeb.UI.SidebarTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "navigation keeps tenant context, marks the active page and exposes labels for icons" do
    doc =
      render_component(&AppWeb.UI.Sidebar.sidebar/1,
        section: "Your profile",
        tenant_id: "workspace-123"
      )
      |> LazyHTML.from_fragment()

    assert [_] =
             LazyHTML.query(
               doc,
               "#workspace-sidebar a[href='/dashboard/profile?tenant=workspace-123'][aria-current='page'][aria-label='Your profile']"
             )
             |> LazyHTML.to_tree()

    assert [_] =
             LazyHTML.query(doc, "[data-sidebar-close][aria-label='Close sidebar']")
             |> LazyHTML.to_tree()

    assert [] = LazyHTML.query(doc, "a[href='/dashboard/admin']") |> LazyHTML.to_tree()
  end

  test "operators get an admin link" do
    doc =
      render_component(&AppWeb.UI.Sidebar.sidebar/1,
        section: "Operator admin",
        current_user: %{operator: true}
      )
      |> LazyHTML.from_fragment()

    assert [_] =
             LazyHTML.query(doc, "a[href='/dashboard/admin'][aria-current='page']")
             |> LazyHTML.to_tree()
  end
end
