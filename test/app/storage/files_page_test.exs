defmodule App.Storage.FilesPageTest do
  use AppWeb.ConnCase, async: false
  import App.AuthHelpers
  alias App.Storage

  setup do
    owner = user("page-owner-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Files app", slug: "files-app"},
        actor: owner
      )

    %{owner: owner, app: app}
  end

  defp create_file(owner, app, filename, size) do
    Ash.create!(
      App.Storage.StoredFile,
      %{
        filename: filename,
        size: size,
        content_type: "text/plain",
        object_key: "#{owner.id}/#{app.id}/#{Ecto.UUID.generate()}",
        application_id: app.id
      },
      actor: owner,
      authorize?: false
    )
  end

  defp create_files(owner, app, count, prefix) do
    for i <- 1..count do
      create_file(
        owner,
        app,
        "#{prefix}-#{String.pad_leading(Integer.to_string(i), 3, "0")}.txt",
        i * 10
      )
    end
  end

  test "paginates more than 100 files with stable totals", %{owner: owner, app: app} do
    files = create_files(owner, app, 105, "report")
    assert length(files) == 105

    page1 = Storage.files_page(owner, app.id, page: 1)
    page5 = Storage.files_page(owner, app.id, page: 5)

    assert page1.total == 105
    assert page1.pages == 5
    assert page1.limit == 25
    assert length(page1.files) == 25
    assert length(page5.files) == 5
    assert page5.page == 5

    ids =
      page1.files ++
        Storage.files_page(owner, app.id, page: 2).files ++
        Storage.files_page(owner, app.id, page: 3).files ++
        Storage.files_page(owner, app.id, page: 4).files ++ page5.files

    assert length(Enum.uniq_by(ids, & &1.id)) == 105
  end

  test "out-of-range pages are clamped", %{owner: owner, app: app} do
    create_files(owner, app, 30, "item")

    assert Storage.files_page(owner, app.id, page: 99).page == 2
    assert length(Storage.files_page(owner, app.id, page: 99).files) == 5
    assert Storage.files_page(owner, app.id, page: 2).page == 2
    assert Storage.files_page(owner, app.id, page: 0).page == 1
    assert Storage.files_page(owner, app.id, page: "-4").page == 1
    assert Storage.files_page(owner, app.id, page: "abc").page == 1
    assert Storage.files_page(owner, app.id, page: "2").page == 2
    assert Storage.files_page(owner, app.id, page: nil).page == 1
  end

  test "search filters by filename and keeps filtered totals", %{owner: owner, app: app} do
    create_files(owner, app, 30, "report")
    create_files(owner, app, 10, "image")

    result = Storage.files_page(owner, app.id, search: "report-001")
    assert result.total == 1
    assert [file] = result.files
    assert file.filename == "report-001.txt"

    result = Storage.files_page(owner, app.id, search: "image")
    assert result.total == 10
    assert length(result.files) == 10

    result = Storage.files_page(owner, app.id, search: "zzz-nothing")
    assert result.total == 0
    assert result.pages == 1
    assert result.files == []

    result = Storage.files_page(owner, app.id, search: String.duplicate("a", 500))
    assert result.search == String.duplicate("a", 200)
    assert result.total == 0
  end

  test "sort options order results with stable tiebreakers", %{owner: owner, app: app} do
    create_files(owner, app, 3, "alpha")
    create_files(owner, app, 3, "beta")

    by_name = Storage.files_page(owner, app.id, sort: "name").files
    assert Enum.map(by_name, & &1.filename) == Enum.sort(Enum.map(by_name, & &1.filename))

    by_size_desc = Storage.files_page(owner, app.id, sort: "size").files
    sizes = Enum.map(by_size_desc, & &1.size)
    assert sizes == Enum.sort(sizes, :desc)

    newest = Storage.files_page(owner, app.id, sort: "newest").files
    assert newest == Enum.sort_by(newest, & &1.created_at, {:desc, DateTime})

    oldest = Storage.files_page(owner, app.id, sort: "oldest").files
    assert oldest == Enum.sort_by(oldest, & &1.created_at, {:asc, DateTime})

    bogus = Storage.files_page(owner, app.id, sort: "bogus")
    assert bogus.sort == "newest"
  end

  test "search and page can be combined", %{owner: owner, app: app} do
    create_files(owner, app, 60, "match")
    create_files(owner, app, 5, "skip")

    page2 = Storage.files_page(owner, app.id, search: "match", page: 2)
    assert page2.total == 60
    assert page2.page == 2
    assert length(page2.files) == 25

    clamped = Storage.files_page(owner, app.id, search: "match", page: 3)
    assert clamped.page == 3
    assert length(clamped.files) == 10
  end

  test "same-owner cross-application isolation", %{owner: owner, app: app} do
    other_app =
      Ash.create!(App.Applications.Application, %{name: "Other app", slug: "other-app"},
        actor: owner
      )

    create_files(owner, app, 30, "mine")
    create_files(owner, other_app, 40, "theirs")

    result = Storage.files_page(owner, app.id)
    assert result.total == 30
    assert Enum.all?(result.files, &(&1.application_id == app.id))
    assert Storage.files_page(owner, other_app.id, page: 2).total == 40
  end

  test "cross-user isolation even within the same application", %{owner: owner, app: app} do
    outsider = user("page-outsider-#{Ecto.UUID.generate()}@example.com")
    create_files(owner, app, 30, "private")

    assert Storage.files_page(outsider, app.id).total == 0
    assert Storage.files_page(outsider, app.id).files == []

    other_owner = user("page-other-#{Ecto.UUID.generate()}@example.com")

    other_app =
      Ash.create!(
        App.Applications.Application,
        %{name: "Other owner app", slug: "other-owner-app"}, actor: other_owner)

    assert Storage.files_page(owner, other_app.id).total == 0
  end

  test "page size is fixed and search bytes are bounded", %{owner: owner, app: app} do
    assert Storage.files_per_page() == 25
    assert "newest" in App.Storage.file_sorts()
    result = Storage.files_page(owner, app.id, search: "  padded  ")
    assert result.search == "padded"
  end
end
