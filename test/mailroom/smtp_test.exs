defmodule Mailroom.SMTPTest do
  use ExUnit.Case
  doctest Mailroom.SMTP

  alias Mailroom.{SMTP,TestServer}

  test "SMTP server doesn't support EHLO" do
    server = TestServer.start

    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,
                       "220 myserver.com.\r\n")
      |> TestServer.on("EHLO #{SMTP.fqdn}\r\n",
                       "500 WAT\r\n")
      |> TestServer.on("HELO #{SMTP.fqdn}\r\n",
                       "250 myserver.com\r\n")
      |> TestServer.on("QUIT\r\n",
                       "221 Bye\r\n")
    end)
    {:ok, client} = SMTP.connect(server.address, port: server.port)
    SMTP.quit(client)
  end

  test "send mail" do
    server = TestServer.start

    msg = """
    Date: Fri, 30 Sep 2016 12:02:00 +0200
    From: me@localhost
    To: you@localhost
    Subject: Test message

    This is a test message
    """ |> String.replace(~r/(?<!\r)\n/, "\r\n")

    lines = String.split(msg, "\r\n") |> Enum.map(&(&1 <> "\r\n"))

    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,
                       "220 myserver.com.\r\n")
      |> TestServer.on("EHLO #{SMTP.fqdn}\r\n",
                       "250-myserver.com\r\n250-SIZE\r\n250 HELP\r\n")
      |> TestServer.on("MAIL FROM: <me@localhost>\r\n",
                       "250 OK\r\n")
      |> TestServer.on("RCPT TO: <you@localhost>\r\n",
                       "250 OK\r\n")
      |> TestServer.on("DATA\r\n",
                       "354 Send message content; end with <CRLF>.<CRLF>\r\n")
      |> TestServer.on(lines ++ [".\r\n"],
                       "250 OK\r\n")
      |> TestServer.on("QUIT\r\n",
                       "221 Bye\r\n")
    end)

    {:ok, client} = SMTP.connect(server.address, port: server.port)
    :ok = SMTP.send_message(client, "me@localhost", "you@localhost", msg)
    SMTP.quit(client)
  end

  test "SMTP with TLS" do
    server = TestServer.start

    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,
                       "220 myserver.com.\r\n")
      |> TestServer.on("EHLO #{SMTP.fqdn}\r\n",
                       "250-myserver.com\r\n250-SIZE\r\n250-STARTTLS\r\n250 HELP\r\n")
      |> TestServer.on("STARTTLS\r\n",
                       "220 TLS go ahead\r\n", ssl: true)
      |> TestServer.on("EHLO #{SMTP.fqdn}\r\n",
                       "250-myserver.com\r\n250-SIZE\r\n250 HELP\r\n")
      |> TestServer.on("QUIT\r\n",
                       "221 Bye\r\n")
    end)

    {:ok, client} = SMTP.connect(server.address, port: server.port)
    SMTP.quit(client)
  end
end
