defmodule AppWeb.BodyParser do
  @moduledoc "Defers v2 API parsing until after credential validation."
  def init(opts), do: Plug.Parsers.init(opts)
  def call(%{path_info: ["api", "v2" | _]} = conn, _), do: conn
  def call(conn, opts), do: Plug.Parsers.call(conn, opts)
end
