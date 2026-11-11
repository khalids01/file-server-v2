defmodule AppWeb.SessionController do
  use AppWeb, :controller
  def new(conn, _), do: render(conn, :new, github?: App.Accounts.Github.enabled?())
  def register(conn, _), do: render(conn, :register, signup?: App.Platform.signup_enabled?())
  def forgot(conn, _), do: render(conn, :forgot)
end
