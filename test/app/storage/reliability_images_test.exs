defmodule App.Storage.ReliabilityImagesTest do
  use AppWeb.ConnCase, async: false
  import App.AuthHelpers
  alias App.Storage
  alias App.Storage.{Quota, StoredFile}

  setup do
    root = Path.join(System.tmp_dir!(), "serve-reliable-" <> Ecto.UUID.generate())
    old = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)
    owner = user("reliable-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Images", slug: "images"}, actor: owner)

    File.mkdir_p!(root)
    source = Path.join(root, "source.png")
    {:ok, image} = Image.new(640, 400, color: :red)
    {:ok, _} = Image.write(image, source)

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, old)
      File.rm_rf!(root)
    end)

    %{owner: owner, app: app, source: source, root: root}
  end

  test "real native variants preserve original, dimensions and private ownership", ctx do
    assert {:ok, file} =
             Storage.upload(ctx.owner, ctx.app.id, ctx.source, "photo.png", "image/png")

    assert file.processing_state == "queued"
    jobs = App.Repo.all(Oban.Job)

    assert Enum.any?(
             jobs,
             &(&1.worker == "App.Storage.Workers.CleanupWorker" and &1.args["file_id"] == file.id)
           )

    job =
      Enum.find(
        jobs,
        &(&1.worker == "App.Storage.Workers.ImageProcessingWorker" and
            &1.args["file_id"] == file.id)
      )

    assert job
    assert :ok = App.Storage.Workers.ImageProcessingWorker.perform(job)
    fresh = App.Repo.get!(StoredFile, file.id) |> Ash.load!(:variants, authorize?: false)
    assert fresh.processing_state == "ready"
    assert length(fresh.variants) == 3

    for variant <- fresh.variants do
      assert variant.status == "ready"
      assert {:ok, download} = Storage.download_variant(ctx.owner, file.id, variant.name)
      assert {:ok, image} = Image.open(download.path)
      {w, h, _} = Image.shape(image)
      assert {w, h} == {variant.width, variant.height}
      assert w <= 640 and h <= 400
      if variant.name == "thumbnail", do: assert(w <= 320 and h <= 320)
    end

    assert {:ok, original} = Storage.download(ctx.owner, file.id)
    assert File.read!(original.path) == File.read!(ctx.source)
    outsider = user("variant-outsider@example.com")
    assert {:error, _} = Storage.download_variant(outsider, file.id, "thumbnail")
    assert {:error, _} = Storage.download_variant(ctx.owner, file.id, "arbitrary")
    usage = Quota.status_for_user(ctx.owner.id)
    assert usage.used_bytes == file.size + Enum.sum(Enum.map(fresh.variants, & &1.size))
    assert usage.reserved_bytes == 0
    assert :ok = Storage.delete(ctx.owner, file.id)
    assert :ok = Storage.cleanup_delete(file.id)
    assert Quota.status_for_user(ctx.owner.id).used_bytes == 0
  end

  test "quota is shared across applications and rejection leaves no reservation", ctx do
    size = File.stat!(ctx.source).size
    :ok = Quota.ensure_account!(ctx.owner.id)

    App.Repo.query!("UPDATE account_storage SET quota_bytes=$2 WHERE user_id=$1", [
      Ecto.UUID.dump!(ctx.owner.id),
      size
    ])

    assert {:ok, file} = Storage.upload(ctx.owner, ctx.app.id, ctx.source, "one.png", "image/png")

    app2 =
      Ash.create!(App.Applications.Application, %{name: "Second", slug: "second"},
        actor: ctx.owner
      )

    assert {:error, :quota_exceeded} =
             Storage.upload(ctx.owner, app2.id, ctx.source, "two.png", "image/png")

    assert %{used_bytes: ^size, reserved_bytes: 0} = Quota.status_for_user(ctx.owner.id)
    assert :ok = Storage.process_image(file.id)
    fresh = App.Repo.get!(StoredFile, file.id)
    assert fresh.processing_state == "failed"
    assert {:ok, _} = Storage.download(ctx.owner, file.id)
    assert Quota.status_for_user(ctx.owner.id).used_bytes == size
  end

  test "corrupt images fail safely and nonimages keep their originals", ctx do
    File.write!(ctx.source, "not a PNG")

    assert {:ok, file} =
             Storage.upload(ctx.owner, ctx.app.id, ctx.source, "broken.png", "image/png")

    assert :ok = Storage.process_image(file.id)
    assert App.Repo.get!(StoredFile, file.id).processing_state == "failed"
    assert {:ok, original} = Storage.download(ctx.owner, file.id)
    assert File.read!(original.path) == "not a PNG"
    assert Quota.status_for_user(ctx.owner.id).reserved_bytes == 0
  end

  test "duplicate deletion cannot subtract another file's bytes", ctx do
    {:ok, a} = Storage.upload(ctx.owner, ctx.app.id, ctx.source, "a.txt", "text/plain")
    {:ok, b} = Storage.upload(ctx.owner, ctx.app.id, ctx.source, "b.txt", "text/plain")
    assert :ok = Storage.delete(ctx.owner, a.id)
    assert :ok = Storage.cleanup_delete(a.id)
    assert Quota.status_for_user(ctx.owner.id).used_bytes == b.size
    assert {:error, :accounting_corrupt} = Quota.adjust(ctx.owner.id, -b.size - 1, 0)
    assert Quota.status_for_user(ctx.owner.id).used_bytes == b.size
  end

  test "orientation is applied, metadata stripped, small images never upscaled", ctx do
    {:ok, image} = Image.new(64, 40, color: :blue)
    {:ok, image} = Image.set_orientation(image, 6)
    source = Path.join(ctx.root, "rotated.jpg")
    {:ok, _} = Image.write(image, source)
    assert File.read!(source) =~ "Exif"
    {:ok, file} = Storage.upload(ctx.owner, ctx.app.id, source, "rotated.jpg", "image/jpeg")
    assert :ok = Storage.process_image(file.id)
    fresh = App.Repo.get!(StoredFile, file.id) |> Ash.load!(:variants, authorize?: false)
    assert fresh.processing_state == "ready"

    for v <- fresh.variants do
      assert {v.width, v.height} == {40, 64}
      {:ok, download} = Storage.download_variant(ctx.owner, file.id, v.name)
      refute File.read!(download.path) =~ "Exif"
    end
  end

  test "failed cleanup retains bytes until physical deletion succeeds", ctx do
    {:ok, file} = Storage.upload(ctx.owner, ctx.app.id, ctx.source, "document.txt", "text/plain")
    {:ok, path} = Storage.Local.path(file.object_key)
    File.rm!(path)
    File.ln_s!(ctx.source, path)
    assert {:error, _} = Storage.delete(ctx.owner, file.id)
    assert Quota.status_for_user(ctx.owner.id).used_bytes == file.size
    assert App.Repo.get!(StoredFile, file.id).delete_requested_at
    File.rm!(path)
    assert :ok = Storage.cleanup_delete(file.id)
    assert Quota.status_for_user(ctx.owner.id).used_bytes == 0
  end

  test "failed pending upload retains reservation and stale recovery is idempotent", ctx do
    # A regular file in place of the storage root prevents any backend write.
    File.rm_rf!(ctx.root)
    File.write!(ctx.root, "blocked")
    source = Path.join(System.tmp_dir!(), "pending-#{Ecto.UUID.generate()}")
    File.write!(source, "pending bytes")
    on_exit(fn -> File.rm(source) end)

    assert {:error, _} =
             Storage.upload(ctx.owner, ctx.app.id, source, "pending.txt", "text/plain")

    assert Quota.status_for_user(ctx.owner.id).reserved_bytes == 13
    [pending] = Ash.read!(StoredFile, authorize?: false)
    assert :ok = Storage.reconcile_stale_upload(pending.id)
    assert App.Repo.get!(StoredFile, pending.id)
    File.rm!(ctx.root)

    App.Repo.query!("UPDATE stored_files SET created_at=now()-interval '1 hour' WHERE id=$1", [
      Ecto.UUID.dump!(pending.id)
    ])

    assert :ok = Storage.reconcile_stale_upload(pending.id)
    assert :ok = Storage.reconcile_stale_upload(pending.id)
    assert Quota.status_for_user(ctx.owner.id).reserved_bytes == 0
    refute App.Repo.get(StoredFile, pending.id)
  end

  test "simultaneous optimization and deletion leave neither objects nor charges", ctx do
    {:ok, file} = Storage.upload(ctx.owner, ctx.app.id, ctx.source, "race.png", "image/png")
    processing = Task.async(fn -> Storage.process_image(file.id) end)
    deletion = Task.async(fn -> Storage.delete(ctx.owner, file.id) end)
    assert :ok = Task.await(processing, 20_000)
    assert :ok = Task.await(deletion, 20_000)
    refute App.Repo.get(StoredFile, file.id)
    assert %{used_bytes: 0, reserved_bytes: 0} = Quota.status_for_user(ctx.owner.id)
    assert Path.wildcard(Path.join(ctx.root, "*/*/*")) == []
  end

  test "pixel and animation preflight reject inputs before native decode", ctx do
    # Deliberately incomplete PNG with oversized declared dimensions: no native decode is needed.
    File.write!(
      ctx.source,
      <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", 100_000::32, 100_000::32, 0, 0, 0, 0, 0>>
    )

    assert {:skip, "image_too_large"} =
             Storage.ImageProcessing.validate_magic(ctx.source, "image/png")

    File.write!(ctx.source, <<"RIFF", 20::32-little, "WEBPANIM", 0::32-little, 0::64>>)

    assert {:skip, "unsupported_format"} =
             Storage.ImageProcessing.validate_magic(ctx.source, "image/webp")

    assert {:skip, "unsupported_format"} =
             Storage.ImageProcessing.candidate?("image/svg+xml", "vector.svg")
  end
end
