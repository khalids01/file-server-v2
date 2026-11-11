defmodule App.Accounts.Preparations.RejectBanned do
  use Ash.Resource.Preparation
  require Ash.Query

  def prepare(query, _, _) do
    if query.action.name == :get_by_subject,
      do: Ash.Query.filter(query, banned == false),
      else: query
  end
end
