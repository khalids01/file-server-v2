defmodule App.Storage.Endpoint do
  @moduledoc "S3 endpoints are restricted to provider hosts or an operator's explicit allowlist."
  @provider_suffixes [
    "amazonaws.com",
    "idrivee2.com",
    "r2.cloudflarestorage.com",
    "digitaloceanspaces.com",
    "backblazeb2.com",
    "wasabisys.com"
  ]
  def validate(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))
    allowed = Application.get_env(:app, :s3_allowed_hosts, [])

    trusted_provider =
      is_binary(uri.host) &&
        Enum.any?(@provider_suffixes, &String.ends_with?(uri.host, "." <> &1))

    explicit = uri.host in allowed

    if uri.scheme in ["https", "http"] and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
         uri.path in [nil, "", "/"] and (explicit or (trusted_provider and uri.scheme == "https")) do
      {:ok, %{uri | path: nil} |> URI.to_string()}
    else
      {:error,
       "Use an HTTPS S3 provider endpoint. Custom hosts must be listed in S3_ALLOWED_HOSTS by the server operator."}
    end
  end

  def validate(_), do: {:error, "Enter an S3 endpoint."}
end
