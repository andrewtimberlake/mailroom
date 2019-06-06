defmodule Mailroom.SMTPTest do
  use ExUnit.Case, async: true
  doctest Mailroom.SMTP

  alias Mailroom.{SMTP, TestServer}

  test "SMTP server doesn't support EHLO" do
    server = TestServer.start()

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(
        :connect,
        "220 myserver.com.\r\n"
      )
      |> TestServer.on(
        "EHLO #{SMTP.fqdn()}\r\n",
        "500 WAT\r\n"
      )
      |> TestServer.on(
        "HELO #{SMTP.fqdn()}\r\n",
        "250 myserver.com\r\n"
      )
      |> TestServer.on(
        "QUIT\r\n",
        "221 Bye\r\n"
      )
    end)

    {:ok, client} = SMTP.connect(server.address, port: server.port)
    SMTP.quit(client)
  end

  test "send mail" do
    server = TestServer.start()

    msg =
      """
      Date: Fri, 30 Sep 2016 12:02:00 +0200
      From: me@localhost
      To: you@localhost
      Subject: Test message

      This is a test message
      """
      |> String.replace(~r/(?<!\r)\n/, "\r\n")

    lines = String.split(msg, "\r\n") |> Enum.map(&(&1 <> "\r\n"))

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(
        :connect,
        "220 myserver.com.\r\n"
      )
      |> TestServer.on(
        "EHLO #{SMTP.fqdn()}\r\n",
        "250-myserver.com\r\n250-SIZE\r\n250 HELP\r\n"
      )
      |> TestServer.on(
        "MAIL FROM: <me@localhost>\r\n",
        "250 OK\r\n"
      )
      |> TestServer.on(
        "RCPT TO: <you@localhost>\r\n",
        "250 OK\r\n"
      )
      |> TestServer.on(
        "DATA\r\n",
        "354 Send message content; end with <CRLF>.<CRLF>\r\n"
      )
      |> TestServer.on(
        lines ++ [".\r\n"],
        "250 OK\r\n"
      )
      |> TestServer.on(
        "QUIT\r\n",
        "221 Bye\r\n"
      )
    end)

    {:ok, client} = SMTP.connect(server.address, port: server.port)
    :ok = SMTP.send_message(client, "me@localhost", "you@localhost", msg)
    SMTP.quit(client)
  end

  test "SMTP with TLS" do
    server = TestServer.start()

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(
        :connect,
        "220 myserver.com.\r\n"
      )
      |> TestServer.on(
        "EHLO #{SMTP.fqdn()}\r\n",
        "250-myserver.com\r\n250-SIZE\r\n250-STARTTLS\r\n250 HELP\r\n"
      )
      |> TestServer.on(
        "STARTTLS\r\n",
        "220 TLS go ahead\r\n",
        ssl: true
      )
      |> TestServer.on(
        "EHLO #{SMTP.fqdn()}\r\n",
        "250-myserver.com\r\n250-SIZE\r\n250 HELP\r\n"
      )
      |> TestServer.on(
        "QUIT\r\n",
        "221 Bye\r\n"
      )
    end)

    {:ok, client} = SMTP.connect(server.address, port: server.port)
    SMTP.quit(client)
  end

  test "SMTP with AUTH PLAIN" do
    server = TestServer.start()

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(
        :connect,
        "220 myserver.com.\r\n"
      )
      |> TestServer.on(
        "EHLO #{SMTP.fqdn()}\r\n",
        "250-myserver.com\r\n250 AUTH PLAIN\r\n"
      )
      |> TestServer.on(
        "AUTH PLAIN AHVzZXJuYW1lAHBhc3N3b3Jk\r\n",
        "235 Authenticated\r\n"
      )
      |> TestServer.on(
        "QUIT\r\n",
        "221 Bye\r\n"
      )
    end)

    {:ok, client} =
      SMTP.connect(server.address, port: server.port, username: "username", password: "password")

    SMTP.quit(client)
  end

  test "SMTP with AUTH PLAIN no username" do
    server = TestServer.start()

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(
        :connect,
        "220 myserver.com.\r\n"
      )
      |> TestServer.on(
        "EHLO #{SMTP.fqdn()}\r\n",
        "250-myserver.com\r\n250 AUTH PLAIN\r\n"
      )
    end)

    assert {:error, "Missing username"} = SMTP.connect(server.address, port: server.port)
  end

  test "SMTP with AUTH PLAIN no password" do
    server = TestServer.start()

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(
        :connect,
        "220 myserver.com.\r\n"
      )
      |> TestServer.on(
        "EHLO #{SMTP.fqdn()}\r\n",
        "250-myserver.com\r\n250 AUTH PLAIN\r\n"
      )
    end)

    assert {:error, "Missing password"} =
             SMTP.connect(server.address, port: server.port, username: "username")
  end

  test "SMTP with AUTH LOGIN" do
    server = TestServer.start()

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(
        :connect,
        "220 myserver.com.\r\n"
      )
      |> TestServer.on(
        "EHLO #{SMTP.fqdn()}\r\n",
        "250-myserver.com\r\n250 AUTH LOGIN PLAIN\r\n"
      )
      |> TestServer.on(
        "AUTH LOGIN\r\n",
        "334 VXNlcm5hbWU6\r\n"
      )
      |> TestServer.on(
        "dXNlcm5hbWU=\r\n",
        "334 UGFzc3dvcmQ6\r\n"
      )
      |> TestServer.on(
        "cGFzc3dvcmQ=\r\n",
        "235 Authenticated\r\n"
      )
      |> TestServer.on(
        "QUIT\r\n",
        "221 Bye\r\n"
      )
    end)

    {:ok, client} =
      SMTP.connect(server.address, port: server.port, username: "username", password: "password")

    SMTP.quit(client)
  end

  # test "connect" do
  #   server   = Application.get_env(:mailroom, :smtp_server)
  #   # port     = Application.get_env(:mailroom, :smtp_port)
  #   # username = Application.get_env(:mailroom, :smtp_username)
  #   # password = Application.get_env(:mailroom, :smtp_password)
  #   ssl      = Application.get_env(:mailroom, :smtp_ssl, false)

  #   server = "smtp.gmail.com"
  #   port = 587

  #   server = "smtp.sparkpostmail.com"
  #   port   = 587

  #   # :dbg.start() |> IO.inspect
  #   # :dbg.tracer |> IO.inspect
  #   # # :dbg.tpl(:gen_smtp_client, :_, [{:_, [], [{:return_trace}]}])
  #   # # :dbg.tpl(:socket, :_, [{:_, [], [{:return_trace}]}])
  #   # # :dbg.tpl(:inet, :_, [{:_, [], [{:return_trace}]}])
  #   # :dbg.tpl(:inet, :setopts, [{:_, [], [{:return_trace}]}])
  #   # :dbg.tpl(:ssl, :transport_accept, [{:_, [], [{:return_trace}]}])
  #   # :dbg.tpl(:ssl, :ssl_accept, [{:_, [], [{:return_trace}]}])
  #   # :dbg.tpl(:ssl, :setopts, [{:_, [], [{:return_trace}]}])
  #   # [:connect, :listen, :send, :recv, :controlling_process, :peername, :close, :shutdown]
  #   # |> Enum.each(fn(name) ->
  #   #   :dbg.tpl(:gen_tcp, name, [{:_, [], [{:return_trace}]}])
  #   #   :dbg.tpl(:ssl,     name, [{:_, [], [{:return_trace}]}])
  #   # end)
  #   # :dbg.p(:all, :c) |> IO.inspect

  #   # :gen_smtp_client.send_blocking({'andrew@debtflow.co.za', ['andrew@andrewtimberlake.com'], 'Date: Fri, 30 Sep 2016 16:20:00 0+200\r\nTo: andrew@andrewtimberlake.com\r\nFrom: andrew@debtflow.co.za\r\nSubject: Test via gen_smtp\r\n\r\nTest email'}, [relay: server, username: 'SMTP_Injection', password: '1e93422c950625e742bb4899e1496b1f15e819e9', port: port, no_mx_lookups: true])

  #   # :dbg.start() |> IO.inspect
  #   # :dbg.tracer |> IO.inspect
  #   # :dbg.tpl(:gen_smtp_client, :_, [{:_, [], [{:return_trace}]}]) |> IO.inspect
  #   # :dbg.tpl(:socket, :_, [{:_, [], [{:return_trace}]}]) |> IO.inspect
  #   # :dbg.tpl(:ssl, :connect, [{:_, [], [{:return_trace}]}]) |> IO.inspect
  #   # :dbg.p(:all, :c) |> IO.inspect

  #   msg = """
  #   Date: Fri, 30 Sep 2016 12:02:00 +0200
  #   From: andrew@debtflow.co.za
  #   To: andrew@andrewtimberlake.com
  #   Subject: Test message

  #   This is a test message
  #   """
  #   {:ok, client} = SMTP.connect(server, ssl: ssl, port: 587, debug: true, username: "SMTP_Injection", password: "1e93422c950625e742bb4899e1496b1f15e819e9")
  #   :ok = SMTP.send_message(client, "andrew@debtflow.co.za", "andrew@andrewtimberlake.com", msg)
  #   SMTP.quit(client)
  # end
end
