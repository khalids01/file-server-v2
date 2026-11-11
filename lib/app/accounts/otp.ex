defmodule App.Accounts.Otp do
  @moduledoc "Email codes: HMAC, durable limits, serialized issuance and single-use verification."
  import Ecto.Query
  require Ash.Query
  alias App.Accounts.{OtpChallengeRecord, User}

  def request_sign_in(email, ip) when is_binary(email) do
    identity = normalize(email)

    if byte_size(identity) > 254 or not Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, identity) do
      {:error, :invalid}
    else
      result =
        App.Repo.transaction(fn ->
          # Same lock ordering prevents deadlocks; DB locks enforce limits across nodes.
          ["email:" <> identity, "ip:" <> to_string(ip)]
          |> Enum.map(&:erlang.phash2/1)
          |> Enum.sort()
          |> Enum.each(&lock/1)

          if limited?(identity, ip) do
            {:error, :rate_limited}
          else
            user = find_user(identity)

            if (user && user.banned) || (is_nil(user) && not App.Platform.signup_enabled?()) do
              :neutral
            else
              now = DateTime.utc_now()

              App.Repo.update_all(
                from(c in OtpChallengeRecord,
                  where:
                    c.identity == ^identity and is_nil(c.consumed_at) and is_nil(c.revoked_at)
                ),
                set: [revoked_at: now]
              )

              code = code()
              id = Ecto.UUID.generate()

              %OtpChallengeRecord{}
              |> OtpChallengeRecord.changeset(%{
                id: id,
                purpose: "sign_in",
                identity: identity,
                code_digest: digest(id, identity, code),
                attempts: 0,
                expires_at: DateTime.add(now, 600),
                request_ip: ip
              })
              |> App.Repo.insert!()

              {:send, code}
            end
          end
        end)

      case result do
        {:ok, {:send, code}} ->
          App.Accounts.User.Senders.SendOtpEmail.send(identity, code)
          :ok

        {:ok, :neutral} ->
          :ok

        {:ok, error} ->
          error

        {:error, _} ->
          {:error, :unavailable}
      end
    end
  end

  def request_sign_in(_, _), do: {:error, :invalid}

  def verify_sign_in(email, code, _ip) when is_binary(email) and is_binary(code) do
    if Regex.match?(~r/^\d{6}$/, code) do
      identity = normalize(email)

      case App.Repo.transaction(fn -> verify_locked(identity, code) end) do
        {:ok, result} -> result
        {:error, _} -> {:error, :invalid}
      end
    else
      {:error, :invalid}
    end
  end

  def verify_sign_in(_, _, _), do: {:error, :invalid}

  defp verify_locked(identity, code) do
    challenge =
      App.Repo.one(
        from c in OtpChallengeRecord,
          where:
            c.identity == ^identity and c.purpose == "sign_in" and is_nil(c.consumed_at) and
              is_nil(c.revoked_at),
          order_by: [desc: c.created_at],
          limit: 1,
          lock: "FOR UPDATE"
      )

    cond do
      is_nil(challenge) ->
        {:error, :invalid}

      DateTime.compare(challenge.expires_at, DateTime.utc_now()) != :gt ->
        {:error, :invalid}

      challenge.attempts >= 3 ->
        {:error, :invalid}

      Plug.Crypto.secure_compare(challenge.code_digest, digest(challenge.id, identity, code)) ->
        user = find_user(identity)

        if (user && user.banned) || (is_nil(user) && not App.Platform.signup_enabled?()) do
          {:error, :invalid}
        else
          # Registration, consumption and persisted session token share one DB transaction.
          user =
            User
            |> Ash.Changeset.for_create(:register_with_otp, %{email: identity}, authorize?: false)
            |> Ash.create!()

          App.Repo.update!(Ecto.Changeset.change(challenge, consumed_at: DateTime.utc_now()))

          case AshAuthentication.Jwt.token_for_user(user) do
            {:ok, token, _} -> {:ok, Ash.Resource.put_metadata(user, :token, token)}
            _ -> App.Repo.rollback(:invalid)
          end
        end

      true ->
        App.Repo.update!(Ecto.Changeset.change(challenge, attempts: challenge.attempts + 1))
        {:error, :invalid}
    end
  end

  defp find_user(email),
    do: User |> Ash.Query.filter(email == ^email) |> Ash.read_one!(authorize?: false)

  defp lock(key), do: App.Repo.query!("SELECT pg_advisory_xact_lock($1::bigint)", [key])

  defp limited?(identity, ip) do
    since = DateTime.add(DateTime.utc_now(), -3600)

    recent =
      App.Repo.one(
        from c in OtpChallengeRecord,
          where: c.identity == ^identity and c.created_at > ^since,
          select: count()
      )

    ip_count =
      if ip,
        do:
          App.Repo.one(
            from c in OtpChallengeRecord,
              where: c.request_ip == ^ip and c.created_at > ^since,
              select: count()
          ),
        else: 0

    last =
      App.Repo.one(
        from c in OtpChallengeRecord,
          where: c.identity == ^identity,
          order_by: [desc: c.created_at],
          limit: 1,
          select: c.created_at
      )

    recent >= 5 or ip_count >= 20 or
      (last != nil and DateTime.diff(DateTime.utc_now(), last) < 60)
  end

  defp digest(id, identity, code) do
    secret = Application.fetch_env!(:app, :token_signing_secret)

    :crypto.mac(:hmac, :sha256, secret, "serve-email-otp:#{id}:#{identity}:#{code}")
    |> Base.encode16(case: :lower)
  end

  defp code do
    <<n::32>> = :crypto.strong_rand_bytes(4)

    if n < 4_294_000_000,
      do: n |> rem(1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0"),
      else: code()
  end

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
