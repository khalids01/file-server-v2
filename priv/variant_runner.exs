defmodule App.Storage.VariantRunner do
  def main do
    try do
      [source, dir, name, max_dim_s, format_s, max_bytes_s] = System.argv() |> Enum.take(-6)
      max_dim = String.to_integer(max_dim_s)
      format = String.to_atom(format_s)
      max_bytes = String.to_integer(max_bytes_s)

      _ = Application.ensure_all_started(:logger)
      _ = Application.ensure_all_started(:vix)
      {:ok, _} = Application.ensure_all_started(:image)
      Vix.Vips.cache_set_max(0)
      Vix.Vips.cache_set_max_mem(0)
      Vix.Vips.cache_set_max_files(0)
      Vix.Vips.concurrency_set(1)

      ext = if format == :webp, do: ".webp", else: ".jpg"
      content_type = if format == :webp, do: "image/webp", else: "image/jpeg"
      path = Path.join(dir, name <> ext)

      img = open!(source)
      img = autorotate!(img)

      {w, h, _} = Image.shape(img)
      scale = min(max_dim / max(w, h), 1.0)
      tw = max(trunc(w * scale), 1)
      th = max(trunc(h * scale), 1)

      img =
        if scale < 1.0 do
          case Image.thumbnail(img, tw, height: th) do
            {:ok, resized} -> resized
            resized -> resized
          end
        else
          img
        end

      opts =
        if format == :webp,
          do: [quality: 80, effort: 4, strip_metadata: true],
          else: [quality: 82, progressive: true, strip_metadata: true]

      case Image.write(img, path, opts) do
        :ok -> :ok
        {:ok, _img} -> :ok
        other -> raise "write_failed: #{inspect(other)}"
      end

      File.chmod!(path, 0o600)
      %{size: size} = File.stat!(path)

      if size > max_bytes do
        File.rm(path)
        IO.write("output_too_large")
        System.halt(2)
      end

      out_img = open!(path)
      {ow, oh, _} = Image.shape(out_img)

      IO.write(
        Jason.encode!(%{
          ok: true,
          path: path,
          name: Path.basename(path),
          content_type: content_type,
          size: size,
          width: ow,
          height: oh
        })
      )
    rescue
      _ -> System.halt(1)
    end
  end

  defp open!(path) do
    case Image.open(path, access: :random) do
      {:ok, img} -> img
      img -> img
    end
  end

  defp autorotate!(img) do
    case Image.autorotate(img) do
      {:ok, {rotated, _flags}} -> rotated
      rotated -> rotated
    end
  end
end
