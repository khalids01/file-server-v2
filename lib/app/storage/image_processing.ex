defmodule App.Storage.ImageProcessing do
  @moduledoc false
  @allow_mime %{
    "image/png" => :png,
    "image/jpeg" => :jpeg,
    "image/jpg" => :jpeg,
    "image/webp" => :webp
  }

  def candidate?(content_type, filename) when is_binary(content_type) do
    ct = String.downcase(content_type)
    ext = filename |> to_string() |> Path.extname() |> String.downcase()

    cond do
      ext in [".svg", ".gif"] ->
        {:skip, "unsupported_format"}

      ct in ["image/svg+xml", "image/gif"] ->
        {:skip, "unsupported_format"}

      Map.has_key?(@allow_mime, ct) ->
        {:ok, ct}

      ct == "application/octet-stream" and ext in [".png", ".jpg", ".jpeg", ".webp"] ->
        {:ok, sniff_type_from_ext(ext)}

      String.starts_with?(ct, "image/") ->
        {:skip, "unsupported_format"}

      true ->
        :not_image
    end
  end

  def candidate?(_, _), do: :not_image

  defp sniff_type_from_ext(".png"), do: "image/png"
  defp sniff_type_from_ext(".jpg"), do: "image/jpeg"
  defp sniff_type_from_ext(".jpeg"), do: "image/jpeg"
  defp sniff_type_from_ext(".webp"), do: "image/webp"

  @max_header_bytes 50 * 1024 * 1024

  def validate_magic(path, claimed_ct) do
    with {:ok, %{size: size}} when size > 0 and size <= @max_header_bytes <- File.stat(path),
         {:ok, head} <- read_head(path),
         {:ok, actual} <- detect(head),
         :ok <- ensure_allowed(actual, claimed_ct),
         :ok <- ensure_static(actual, path),
         {:ok, {w, h}} <- dimensions(path, actual),
         :ok <- validate_pixels(w, h) do
      {:ok, %{format: actual, width: w, height: h, pixels: w * h}}
    else
      {:ok, %{size: size}} when size > @max_header_bytes -> {:skip, "image_too_large"}
      {:error, :unsupported} -> {:skip, "unsupported_format"}
      {:skip, reason} -> {:skip, reason}
      _ -> {:error, :invalid_image}
    end
  end

  defp read_head(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        data = IO.binread(io, 64)
        File.close(io)

        case data do
          bin when is_binary(bin) -> {:ok, bin}
          _ -> {:error, :invalid}
        end

      _ ->
        {:error, :invalid}
    end
  end

  defp detect(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: {:ok, :png}
  defp detect(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, :jpeg}
  defp detect(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: {:ok, :webp}
  defp detect(<<"GIF87a", _::binary>>), do: {:error, :unsupported}
  defp detect(<<"GIF89a", _::binary>>), do: {:error, :unsupported}

  defp detect(<<0x3C, rest::binary>>) do
    s = String.downcase(<<0x3C>> <> binary_part(rest, 0, min(byte_size(rest), 63)))

    if String.contains?(s, "svg") or String.contains?(s, "?xml"),
      do: {:error, :unsupported},
      else: {:error, :invalid}
  end

  defp detect(_), do: {:error, :invalid}

  defp ensure_allowed(actual, claimed_ct) do
    claimed = Map.get(@allow_mime, String.downcase(to_string(claimed_ct)))

    cond do
      is_nil(claimed) -> :ok
      claimed == actual -> :ok
      claimed in [:jpeg] and actual == :jpeg -> :ok
      true -> {:error, :invalid_image}
    end
  end

  defp ensure_static(:webp, path) do
    case read_bounded(path) do
      {:ok, bin} ->
        # Animated WebP contains ANIM/ANMF chunks; reject animation.
        if :binary.match(bin, "ANIM") != :nomatch or :binary.match(bin, "ANMF") != :nomatch,
          do: {:skip, "unsupported_format"},
          else: :ok

      _ ->
        {:error, :invalid_image}
    end
  end

  defp ensure_static(:png, path) do
    with {:ok, bin} <- read_bounded(path) do
      if :binary.match(bin, "acTL") == :nomatch, do: :ok, else: {:skip, "unsupported_format"}
    end
  end

  defp ensure_static(_, _), do: :ok

  defp dimensions(path, :png), do: png_dimensions(path)
  defp dimensions(path, :jpeg), do: jpeg_dimensions(path)
  defp dimensions(path, :webp), do: webp_dimensions(path)

  defp png_dimensions(path) do
    with {:ok, <<137, 80, 78, 71, 13, 10, 26, 10, _len::32, "IHDR", w::32, h::32, _::binary>>} <-
           read_bounded(path) do
      {:ok, {w, h}}
    else
      _ -> {:error, :invalid}
    end
  end

  defp jpeg_dimensions(path) do
    with {:ok, bin} <- read_bounded(path), do: parse_jpeg(bin, 2)
  end

  defp parse_jpeg(bin, offset) when offset + 4 <= byte_size(bin) do
    case bin do
      <<_::binary-size(^offset), 0xFF, marker, rest::binary>> ->
        cond do
          marker == 0xD9 or marker == 0xDA ->
            {:error, :invalid}

          marker in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF] ->
            <<_len::16, _prec, h::16, w::16, _::binary>> = rest
            {:ok, {w, h}}

          true ->
            <<len::16, _::binary>> = rest
            parse_jpeg(bin, offset + 2 + len)
        end

      _ ->
        {:error, :invalid}
    end
  end

  defp parse_jpeg(_, _), do: {:error, :invalid}

  defp webp_dimensions(path) do
    with {:ok, bin} <- read_bounded(path),
         <<"RIFF", _::32-little, "WEBP", rest::binary>> <- bin do
      parse_vp8(rest)
    else
      _ -> {:error, :invalid}
    end
  end

  defp parse_vp8(
         <<"VP8 ", _len::32-little, _frame::binary-size(6), w::16-little, h::16-little,
           _::binary>>
       ) do
    {:ok, {Bitwise.band(w, 0x3FFF), Bitwise.band(h, 0x3FFF)}}
  end

  defp parse_vp8(<<"VP8L", _len::32-little, 0x2F, bits::32-little, _::binary>>) do
    w = Bitwise.band(bits, 0x3FFF) + 1
    h = Bitwise.band(Bitwise.bsr(bits, 14), 0x3FFF) + 1
    {:ok, {w, h}}
  end

  defp parse_vp8(
         <<"VP8X", _len::32-little, _flags::32, w24::24-little, h24::24-little, _::binary>>
       ) do
    {:ok, {w24 + 1, h24 + 1}}
  end

  defp parse_vp8(<<_tag::binary-size(4), len::32-little, rest::binary>>) do
    pad = if rem(len, 2) == 1, do: 1, else: 0

    if byte_size(rest) >= len + pad,
      do: parse_vp8(binary_part(rest, len + pad, byte_size(rest) - len - pad)),
      else: {:error, :invalid}
  end

  defp parse_vp8(_), do: {:error, :invalid}

  defp read_bounded(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_header_bytes -> File.read(path)
      {:ok, %{size: _}} -> {:error, :too_large}
      err -> err
    end
  end

  defp validate_pixels(w, h) when is_integer(w) and is_integer(h) and w > 0 and h > 0 do
    max = App.Storage.image_max_input_pixels()
    if w * h <= max and w <= 16_384 and h <= 16_384, do: :ok, else: {:skip, "image_too_large"}
  end

  defp validate_pixels(_, _), do: {:error, :invalid}
end
