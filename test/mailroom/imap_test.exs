defmodule Mailroom.IMAPTest do
  use ExUnit.Case, async: true
  doctest Mailroom.IMAP

  alias Mailroom.{IMAP,TestServer}

  @debug false

  test "STARTTLS" do
    server = TestServer.start(ssl: false)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK [CAPABILITY IMAPrev4 STARTTLS]\r\n")
      |> TestServer.on("A001 STARTTLS\r\n", [
            "A001 OK Begin TLS\r\n"], ssl: true)
      |> TestServer.on("A002 LOGIN test@example.com P@55w0rD\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A002 OK test@example.com authenticated (Success)\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: false, debug: @debug)
    assert IMAP.state(client) == :authenticated
  end

  test "LOGIN with invalid credentials" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com wrong\r\n", [
            "A001 NO [AUTHENTICATIONFAILED] Authentication failed\r\n"])
      |> TestServer.on("A002 LOGOUT\r\n", [
            "* BYE Logging off now\r\n",
            "A002 OK We're done\r\n"])
    end)

    assert {:error, :authentication, "[AUTHENTICATIONFAILED] Authentication failed"} = IMAP.connect(server.address, "test@example.com", "wrong", port: server.port, ssl: true, debug: @debug)
  end

  test "LOGIN" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com P@55w0rD\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    assert IMAP.state(client) == :authenticated
  end

  test "CAPABILITY request is issued if not supplied" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com P@55w0rD\r\n", [
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 CAPABILITY\r\n",    [
            "* CAPABILITY IMAP4rev1 LITERAL+ ENABLE IDLE NAMESPACE UIDPLUS QUOTA\r\n",
            "A002 OK CAPABILITY complete\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
  end

  test "SELECT" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com P@55w0rD\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 SELECT INBOX\r\n",    [
            "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
            "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
            "* 2 EXISTS\r\n",
            "* 1 RECENT\r\n",
            "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    assert IMAP.state(client) == :selected

    assert IMAP.email_count(client) == 2
    assert IMAP.recent_count(client) == 1
  end

  test "CLOSE" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com P@55w0rD\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 SELECT INBOX\r\n",    [
            "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
            "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
            "* 2 EXISTS\r\n",
            "* 1 RECENT\r\n",
            "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"])
      |> TestServer.on("A003 CLOSE\r\n", [
            "A003 OK Closed\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    IMAP.close(client)
    assert IMAP.state(client) == :authenticated
  end

  test "LOGOUT" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com P@55w0rD\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 SELECT INBOX\r\n",    [
            "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
            "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
            "* 2 EXISTS\r\n",
            "* 1 RECENT\r\n",
            "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"])
      |> TestServer.on("A003 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A003 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    IMAP.logout(client)
    assert IMAP.state(client) == :logged_out
  end
end