defmodule App.MailerConfig do
  @moduledoc "SMTP configuration compatible with the existing JavaScript deployment's email variables."
  def build(env) do
    email = value(env, "EMAIL")
    password = value(env, "EMAIL_PASSWORD")
    host = value(env, "SMTP_HOST") || "smtp.gmail.com"

    sender =
      {value(env, "EMAIL_FROM") || "File Server",
       value(env, "EMAIL_FROM_ADDRESS") || email || "noreply@example.test"}

    smtp =
      cond do
        is_nil(email) and is_nil(password) ->
          nil

        is_nil(email) or is_nil(password) ->
          raise "Set both EMAIL and EMAIL_PASSWORD to enable SMTP"

        true ->
          port = String.to_integer(value(env, "SMTP_PORT") || "465")
          implicit? = port == 465

          verification = [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            server_name_indication: String.to_charlist(host),
            depth: 10,
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]

          [
            adapter: Swoosh.Adapters.SMTP,
            relay: host,
            port: port,
            username: email,
            password: password,
            ssl: implicit?,
            tls: if(implicit?, do: :never, else: :always),
            auth: :always,
            retries: 1,
            no_mx_lookups: true,
            sockopts: verification,
            tls_options: verification
          ]
      end

    %{sender: sender, smtp: smtp}
  end

  defp value(env, key) do
    case Map.get(env, key) do
      v when is_binary(v) -> if String.trim(v) == "", do: nil, else: String.trim(v)
      _ -> nil
    end
  end
end
