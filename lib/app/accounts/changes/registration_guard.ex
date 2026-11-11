defmodule App.Accounts.Changes.RegistrationGuard do
  use Ash.Resource.Change
  require Ash.Query

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      email = Ash.Changeset.get_attribute(changeset, :email)

      existing =
        if email,
          do:
            App.Accounts.User
            |> Ash.Query.filter(email == ^email)
            |> Ash.read_one!(authorize?: false)

      cond do
        existing && existing.banned ->
          Ash.Changeset.add_error(changeset, "Unable to authenticate")

        is_nil(existing) && not App.Platform.signup_enabled?() ->
          Ash.Changeset.add_error(changeset, "Registration is unavailable")

        true ->
          changeset
      end
    end)
  end
end
