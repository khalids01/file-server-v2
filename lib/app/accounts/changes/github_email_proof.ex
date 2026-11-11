defmodule App.Accounts.Changes.GithubEmailProof do
  @moduledoc "Confirms only the exact email verified by GitHub, after provider-ID resolution."
  use Ash.Resource.Change
  require Ash.Query

  def change(changeset, _, _) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      info = Ash.Changeset.get_argument(changeset, :user_info)
      email = changeset |> Ash.Changeset.get_attribute(:email) |> to_string() |> String.downcase()
      verified_email = to_string(info["email"]) |> String.trim() |> String.downcase()

      if info["email_verified"] == true and email == verified_email do
        Ash.Changeset.force_change_attribute(changeset, :confirmed_at, DateTime.utc_now())
      else
        # A returning stable provider ID may resolve an account whose stored email
        # differs from the provider's current email. Do not confirm that old email.
        existing =
          App.Accounts.User
          |> Ash.Query.filter(email == ^email)
          |> Ash.read_one!(authorize?: false)

        if existing && existing.confirmed_at,
          do:
            Ash.Changeset.force_change_attribute(changeset, :confirmed_at, existing.confirmed_at),
          else: Ash.Changeset.add_error(changeset, "Use an email code to verify this account")
      end
    end)
  end
end
