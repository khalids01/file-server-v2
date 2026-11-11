defmodule App.Platform do
  use Ash.Domain, otp_app: :app

  resources do
    resource App.Platform.Setting
  end

  def signup_enabled? do
    case Ash.get(App.Platform.Setting, "signup_enabled",
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, nil} -> true
      {:ok, %{value: value}} -> value != "false"
      _ -> false
    end
  end

  def set_signup_enabled!(enabled, actor) when is_boolean(enabled) do
    case Ash.get!(App.Platform.Setting, "signup_enabled",
           authorize?: false,
           not_found_error?: false
         ) do
      nil ->
        Ash.create!(App.Platform.Setting, %{key: "signup_enabled", value: to_string(enabled)},
          actor: actor
        )

      setting ->
        Ash.update!(setting, %{value: to_string(enabled)}, actor: actor)
    end
  end
end
