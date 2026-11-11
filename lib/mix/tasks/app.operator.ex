defmodule Mix.Tasks.App.Operator do
  use Mix.Task
  @shortdoc "Promote an existing verified user: mix app.operator EMAIL"
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [email] ->
        require Ash.Query

        user =
          App.Accounts.User
          |> Ash.Query.filter(email == ^email)
          |> Ash.read_one!(authorize?: false)

        if user && user.confirmed_at do
          Ash.update!(user, %{}, action: :mark_operator, authorize?: false)
          Mix.shell().info("Existing verified account promoted to operator.")
        else
          Mix.raise(
            "Account must exist and have a confirmed email. Sign in with an email code first."
          )
        end

      _ ->
        Mix.raise("Usage: mix app.operator EMAIL")
    end
  end
end
