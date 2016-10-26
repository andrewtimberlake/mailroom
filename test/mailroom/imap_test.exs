defmodule Mailroom.IMAPTest do
  use ExUnit.Case, async: true
  doctest Mailroom.IMAP

  alias Mailroom.{IMAP,TestServer}

  test "STARTTLS" do
    server = TestServer.start(ssl: false)
    |> IO.inspect
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK [CAPABILITY IMAPrev4 STARTTLS]\r\n")
      |> TestServer.on("A001 STARTTLS\r\n", [
            "A001 OK Begin TLS\r\n"], ssl: true)
      |> TestServer.on("A002 LOGIN test@example.com P@55w0rD\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A002 OK test@example.com authenticated (Success)\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: false, debug: true)
  end

  test "login" do
    server = TestServer.start(ssl: true)
    |> IO.inspect
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com P@55w0rD\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 SELECT INBOX\r\n",    [
            "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
            "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
            "* 1 EXISTS\r\n",
            "* 0 RECENT\r\n",
            "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: true)
    client
    |> IMAP.select(:inbox)

    assert IMAP.email_count(client) == 1
    assert IMAP.recent_count(client) == 0
  end

  test "login with invalid credentials" do
    server = TestServer.start(ssl: true)
    |> IO.inspect
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com wrong\r\n", [
            "A001 NO [AUTHENTICATIONFAILED] Authentication failed\r\n"])
    end)

    assert {:error, :authentication, "[AUTHENTICATIONFAILED] Authentication failed"} = IMAP.connect(server.address, "test@example.com", "wrong", port: server.port, ssl: true, debug: true)
  end

#   [true, false]
#   |> Enum.each(fn(ssl) ->
#     description = if ssl, do: " (with SSL)", else: ""

#     test "login #{description}" do
#       server = TestServer.start(ssl: unquote(ssl))
#       TestServer.expect(server, fn(expectations) ->
#         expectations
#         |> TestServer.on(:connect,                    "+OK Test server ready.\r\n")
#         |> TestServer.on("USER test@example.com\r\n", "+OK\r\n")
#         |> TestServer.on("PASS P@55w0rD\r\n",         "+OK Logged in.\r\n")
#       end)

#       assert {:ok, _client} = POP3.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: unquote(ssl))
#     end

#     test "login wrong password #{description}" do
#       server = TestServer.start(ssl: unquote(ssl))
#       TestServer.expect(server, fn(expectations) ->
#         expectations
#         |> TestServer.on(:connect,                    "+OK Test server ready.\r\n")
#         |> TestServer.on("USER test@example.com\r\n", "+OK\r\n")
#         |> TestServer.on("PASS P@55w0rD\r\n",         "-ERR [AUTH] Authentication failure.\r\n")
#       end)

#       assert {:error, :authentication, "[AUTH] Authentication failure."} == POP3.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: unquote(ssl))
#     end

#     test "stat #{description}" do
#       server = TestServer.start(ssl: unquote(ssl))
#       TestServer.expect(server, fn(expectations) ->
#         expectations
#         |> TestServer.on(:connect,                    "+OK Test server ready.\r\n")
#         |> TestServer.on("USER test@example.com\r\n", "+OK\r\n")
#         |> TestServer.on("PASS P@55w0rD\r\n",         "+OK Logged in.\r\n")
#         |> TestServer.on("STAT\r\n",                  "+OK 1 123\r\n")
#       end)

#       assert {:ok, client} = POP3.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: unquote(ssl))
#       assert POP3.stat(client) == {1, 123}
#     end

#     test "list #{description}" do
#       server = TestServer.start(ssl: unquote(ssl))
#       TestServer.expect(server, fn(expectations) ->
#         expectations
#         |> TestServer.on(:connect,                    "+OK Test server ready.\r\n")
#         |> TestServer.on("USER test@example.com\r\n", "+OK\r\n")
#         |> TestServer.on("PASS P@55w0rD\r\n",         "+OK Logged in.\r\n")
#         |> TestServer.on("LIST\r\n",                  "+OK 2 234\r\n1 121\r\n2 113\r\n.\r\n")
#       end)

#       {:ok, client} = POP3.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: unquote(ssl))
#       assert client |> POP3.list == [{1, 121}, {2, 113}]
#     end

#     test "retrieve #{description}" do
#       server = TestServer.start(ssl: unquote(ssl))

#       msg = """
#       Date: Tue, 27 Sep 2016 13:30:56 +0200
#       To: user@example.com
#       From: sender@example.com
#       Subject: This is a test

#       This is a test message
#       """ |> String.replace("\n", "\r\n")

#       TestServer.expect(server, fn(expectations) ->
#         expectations
#         |> TestServer.on(:connect,                    "+OK Test server ready.\r\n")
#         |> TestServer.on("USER test@example.com\r\n", "+OK\r\n")
#         |> TestServer.on("PASS P@55w0rD\r\n",         "+OK Logged in.\r\n")
#         |> TestServer.on("STAT\r\n",                  "+OK 2 234\r\n")
#         |> TestServer.on("RETR 1\r\n",                """
#         +OK 123 octets
#         #{msg}
#         .
#         """ |> String.replace(~r/(?<!\r)\n/, "\r\n"))
#       end)

#       {:ok, client} = POP3.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: unquote(ssl))
#       {2, 234} = POP3.stat(client)
#       {:ok, lines} = POP3.retrieve(client, 1)
#       assert msg == Enum.join(lines, "\r\n")
#     end

#     test "delete #{description}" do
#       server = TestServer.start(ssl: unquote(ssl))
#       TestServer.expect(server, fn(expectations) ->
#         expectations
#         |> TestServer.on(:connect,                    "+OK Test server ready.\r\n")
#         |> TestServer.on("USER test@example.com\r\n", "+OK\r\n")
#         |> TestServer.on("PASS P@55w0rD\r\n",         "+OK Logged in.\r\n")
#         |> TestServer.on("STAT\r\n",                  "+OK 2 234\r\n")
#         |> TestServer.on("DELE 1\r\n",                  "+OK\r\n")
#       end)

#       {:ok, client} = POP3.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: unquote(ssl))
#       {2, 234} = POP3.stat(client)
#       assert :ok == POP3.delete(client, 1)
#     end

#     test "reset #{description}" do
#       server = TestServer.start(ssl: unquote(ssl))
#       TestServer.expect(server, fn(expectations) ->
#         expectations
#         |> TestServer.on(:connect,                    "+OK Test server ready.\r\n")
#         |> TestServer.on("USER test@example.com\r\n", "+OK\r\n")
#         |> TestServer.on("PASS P@55w0rD\r\n",         "+OK Logged in.\r\n")
#         |> TestServer.on("RSET\r\n",                  "+OK\r\n")
#       end)

#       assert {:ok, client} = POP3.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: unquote(ssl))
#       assert POP3.reset(client) == :ok
#     end

#     test "quit #{description}" do
#       server = TestServer.start(ssl: unquote(ssl))
#       TestServer.expect(server, fn(expectations) ->
#         expectations
#         |> TestServer.on(:connect,                    "+OK Test server ready.\r\n")
#         |> TestServer.on("USER test@example.com\r\n", "+OK\r\n")
#         |> TestServer.on("PASS P@55w0rD\r\n",         "+OK Logged in.\r\n")
#         |> TestServer.on("QUIT\r\n",                  "+OK Bye.\r\n")
#       end)

#       assert {:ok, client} = POP3.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: unquote(ssl))
#       assert POP3.quit(client) == :ok
#     end
#   end)
end
