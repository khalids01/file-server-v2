defmodule AppWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [App.Accounts],
    open_api: "/open_api"
end
