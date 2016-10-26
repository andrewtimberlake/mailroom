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

    assert {:ok, _client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: false, debug: @debug)
  end

  test "login" do
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
            "* 1 EXISTS\r\n",
            "* 0 RECENT\r\n",
            "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)

    assert IMAP.email_count(client) == 1
    assert IMAP.recent_count(client) == 0
  end

  test "login with invalid credentials" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN test@example.com wrong\r\n", [
            "A001 NO [AUTHENTICATIONFAILED] Authentication failed\r\n"])
    end)

    assert {:error, :authentication, "[AUTHENTICATIONFAILED] Authentication failed"} = IMAP.connect(server.address, "test@example.com", "wrong", port: server.port, ssl: true, debug: @debug)
  end
end
