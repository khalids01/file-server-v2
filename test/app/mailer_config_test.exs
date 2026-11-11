defmodule App.MailerConfigTest do
  use ExUnit.Case, async: true

  test "Gmail implicit TLS uses EMAIL credentials and EMAIL_FROM as the display name" do
    config =
      App.MailerConfig.build(%{
        "EMAIL" => "sender@example.test",
        "EMAIL_PASSWORD" => "fake-app-password",
        "EMAIL_FROM" => "File Server",
        "SMTP_HOST" => "smtp.gmail.com",
        "SMTP_PORT" => "465"
      })

    assert config.sender == {"File Server", "sender@example.test"}
    assert config.smtp[:adapter] == Swoosh.Adapters.SMTP
    assert config.smtp[:username] == "sender@example.test"
    assert config.smtp[:password] == "fake-app-password"
    assert config.smtp[:ssl]
    assert config.smtp[:tls] == :never
    assert config.smtp[:sockopts][:verify] == :verify_peer
    assert config.smtp[:sockopts][:server_name_indication] == ~c"smtp.gmail.com"
  end

  test "STARTTLS is required on submission ports and verifies certificates" do
    config =
      App.MailerConfig.build(%{
        "EMAIL" => "sender@example.test",
        "EMAIL_PASSWORD" => "fake",
        "SMTP_PORT" => "587"
      })

    refute config.smtp[:ssl]
    assert config.smtp[:tls] == :always
    assert config.smtp[:tls_options][:verify] == :verify_peer
  end

  test "empty credentials use local mail in development and partial configuration is rejected" do
    assert App.MailerConfig.build(%{"EMAIL" => "", "EMAIL_PASSWORD" => ""}).smtp == nil

    assert_raise RuntimeError, ~r/Set both EMAIL and EMAIL_PASSWORD/, fn ->
      App.MailerConfig.build(%{"EMAIL" => "sender@example.test"})
    end
  end

  test "tests always retain the test mail adapter" do
    assert Application.fetch_env!(:app, App.Mailer)[:adapter] == Swoosh.Adapters.Test
  end
end
