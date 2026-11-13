defmodule AppWeb.Router do
  use AppWeb, :router

  use AshAuthentication.Phoenix.Router
  import AshAuthentication.Plug.Helpers, only: [set_actor: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug :configured_github
    plug :throttle_auth
  end

  defp throttle_auth(conn, _opts) do
    auth_post? =
      conn.method == "POST" and
        (List.first(conn.path_info) == "auth" or
           Enum.take(conn.path_info, 2) == ["sign-in", "otp"] or conn.path_info == ["register"])

    if auth_post? and
         not App.Accounts.RateLimit.allow_auth_ip?(to_string(:inet.ntoa(conn.remote_ip))) do
      conn
      |> put_resp_header("retry-after", "60")
      |> send_resp(429, "Too many authentication requests. Please try again later.")
      |> halt()
    else
      conn
    end
  end

  defp configured_github(conn, _opts) do
    if Enum.take(conn.path_info, 3) == ["auth", "user", "github"] and
         not App.Accounts.Github.enabled?() do
      conn
      |> put_flash(:error, "GitHub sign-in has not been configured yet.")
      |> Phoenix.Controller.redirect(to: "/sign-in")
      |> halt()
    else
      conn
    end
  end

  pipeline :api do
    plug :accepts, ["json"]

    plug :fetch_session
    plug :load_from_session
    plug :set_actor, :user

    plug :prepare_json_api
  end

  defp prepare_json_api(conn, _opts) do
    case conn.path_info do
      ["api", "json", "open_api"] ->
        Plug.Conn.register_before_send(
          conn,
          &Plug.Conn.put_resp_content_type(&1, "application/json")
        )

      ["api", "json", "swaggerui"] ->
        conn

      _ ->
        if conn.assigns[:current_user] do
          conn
        else
          conn
          |> Plug.Conn.put_resp_content_type("application/vnd.api+json")
          |> Plug.Conn.send_resp(
            401,
            Jason.encode!(%{errors: [%{status: "401", title: "Sign-in required"}]})
          )
          |> Plug.Conn.halt()
        end
    end
  end

  pipeline :application_api do
    plug AppWeb.ApplicationAuth
    plug AppWeb.UploadParser
  end

  scope "/api/v2", AppWeb do
    pipe_through :application_api
    get "/files", FileApiController, :index
    post "/files", FileApiController, :create
    get "/files/:id/content", FileApiController, :content
    get "/files/:id", FileApiController, :show
    patch "/files/:id", FileApiController, :update
    delete "/files/:id", FileApiController, :delete
    get "/application", ApplicationApiController, :show
  end

  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", AppWeb.AshJsonApiRouter
  end

  scope "/", AppWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      live "/dashboard", DashboardLive, :overview
      live "/dashboard/applications", DashboardLive, :applications
      live "/dashboard/applications/:id", DashboardLive, :application
      live "/dashboard/profile", DashboardLive, :profile
      live "/dashboard/admin", OperatorLive, :index
    end
  end

  scope "/", AppWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/files/:id/download", FileController, :download

    get "/sign-in/otp", OtpController, :new
    post "/sign-in/otp", OtpController, :request_code
    post "/sign-in/otp/verify", OtpController, :verify

    auth_routes AuthController, App.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [AppWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    get "/sign-in", SessionController, :new
    get "/register", SessionController, :register
    post "/register", OtpController, :register
  end

  # Other scopes may use custom stacks.
  # scope "/api", AppWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  if Application.compile_env(:app, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
