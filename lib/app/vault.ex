defmodule App.Vault do
  @moduledoc "AES-GCM vault used by AshCloak resources."
  use Cloak.Vault, otp_app: :app
  # Cloak 1.1.4 wraps the crypto authentication failure atom in {:ok, :error}.
  # Normalize it so AshCloak and callers cannot treat failed decryption as data.
  @impl Cloak.Vault
  def decrypt(ciphertext) do
    case super(ciphertext) do
      {:ok, :error} -> {:error, RuntimeError.exception("Ciphertext authentication failed")}
      result -> result
    end
  end

  @impl Cloak.Vault
  def decrypt!(ciphertext) do
    case decrypt(ciphertext) do
      {:ok, plaintext} -> plaintext
      {:error, error} -> raise error
    end
  end
end
