defmodule App.Accounts.Preparations.RejectBanned do
  use Ash.Resource.Preparation
  require Ash.Query

  def prepare(query, _opts, _context) do
    query =
      if query.action.name == :sign_in_with_password do
        Ash.Query.before_action(query, fn query ->
          if App.Accounts.RateLimit.allow_password?(Ash.Query.get_argument(query, :email)),
            do: query,
            else: Ash.Query.add_error(query, "Unable to authenticate. Please try again later.")
        end)
      else
        query
      end

    if query.action.name in [:sign_in_with_password, :sign_in_with_api_key, :get_by_subject] do
      Ash.Query.filter(query, banned == false)
    else
      query
    end
  end
end
