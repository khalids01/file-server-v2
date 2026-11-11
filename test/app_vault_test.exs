defmodule App.VaultTest do
  use ExUnit.Case, async: true

  test "encrypts, decrypts, and detects modified ciphertext" do
    plaintext = "storage-credential"
    ciphertext = App.Vault.encrypt!(plaintext)
    refute ciphertext == plaintext
    assert App.Vault.decrypt!(ciphertext) == plaintext
    size = byte_size(ciphertext) - 1
    <<prefix::binary-size(^size), last>> = ciphertext
    tampered = prefix <> <<Bitwise.bxor(last, 1)>>
    assert {:error, _} = App.Vault.decrypt(tampered)
    assert_raise RuntimeError, fn -> App.Vault.decrypt!(tampered) end
  end
end
