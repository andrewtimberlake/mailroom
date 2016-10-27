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
      |> TestServer.on("A002 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
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
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"wrong\"\r\n", [
            "A001 NO [AUTHENTICATIONFAILED] Authentication failed\r\n"])
      |> TestServer.on("A002 LOGOUT\r\n", [
            "* BYE Logging off now\r\n",
            "A002 OK We're done\r\n"])
    end)

    assert {:error, :authentication, "[AUTHENTICATIONFAILED] Authentication failed"} = IMAP.connect(server.address, "test@example.com", "wrong", port: server.port, ssl: true, debug: @debug)
  end

  test "LOGIN with interesting characters" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"p!@#$%^&*()\\\"\"\r\n", [
            "A001 NO [AUTHENTICATIONFAILED] Authentication failed\r\n"])
      |> TestServer.on("A002 LOGOUT\r\n", [
            "* BYE Logging off now\r\n",
            "A002 OK We're done\r\n"])
    end)

    assert {:error, :authentication, "[AUTHENTICATIONFAILED] Authentication failed"} = IMAP.connect(server.address, "test@example.com", "p!@#$%^&*()\"", port: server.port, ssl: true, debug: @debug)
  end

  test "LOGIN" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
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
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
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
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 SELECT INBOX\r\n",    [
            "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
            "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
            "* 4 EXISTS\r\n",
            "* 1 RECENT\r\n",
            "* OK [UNSEEN 2]\r\n",
            "* OK [UIDVALIDITY 1474976037] UIDs valid\r\n",
            "* OK [UIDNEXT 5] Predicted next UID\r\n",
            "* OK [HIGHESTMODSEQ 2] Highest\r\n",
            "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    assert IMAP.state(client) == :selected
    assert IMAP.mailbox(client) == {:inbox, :rw}

    assert IMAP.email_count(client) == 4
    assert IMAP.recent_count(client) == 1
    assert IMAP.unseen_count(client) == 2
  end

  test "CLOSE" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
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
    refute IMAP.mailbox(client)
  end

  test "EXAMINE" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 EXAMINE INBOX\r\n",    [
            "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
            "* OK [PERMANENTFLAGS ()] Read-only mailbox\r\n",
            "* 4 EXISTS\r\n",
            "* 1 RECENT\r\n",
            "* OK [UNSEEN 2]\r\n",
            "* OK [UIDVALIDITY 1474976037] UIDs valid\r\n",
            "* OK [UIDNEXT 5] Predicted next UID\r\n",
            "* OK [HIGHESTMODSEQ 2] Highest\r\n",
            "A002 OK [READ-ONLY] examining INBOX. (Success)\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.examine(:inbox)
    assert IMAP.state(client) == :selected
    assert IMAP.mailbox(client) == {:inbox, :r}

    assert IMAP.email_count(client) == 4
    assert IMAP.recent_count(client) == 1
    assert IMAP.unseen_count(client) == 2
  end

  test "LIST" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 LIST \"\" \"*\"\r\n",    [
            "* LIST (\\HasChildren) \".\" INBOX\r\n",
            "* LIST (\\HasNoChildren \\Trash) \".\" INBOX.Trash\r\n",
            "* LIST (\\HasNoChildren \\Drafts) \".\" INBOX.Drafts\r\n",
            "* LIST (\\HasNoChildren \\Sent) \".\" INBOX.Sent\r\n",
            "* LIST (\\HasNoChildren \\Junk) \".\" INBOX.Junk\r\n",
            "* LIST (\\HasNoChildren \\Archive) \".\" \"INBOX.Archive\"\r\n",
            "A002 OK LIST complete\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    {:ok, list} = IMAP.list(client)
    assert list == [{"INBOX", ".", ["\\HasChildren"]},
                    {"INBOX.Trash", ".", ["\\HasNoChildren", "\\Trash"]},
                    {"INBOX.Drafts", ".", ["\\HasNoChildren", "\\Drafts"]},
                    {"INBOX.Sent", ".", ["\\HasNoChildren", "\\Sent"]},
                    {"INBOX.Junk", ".", ["\\HasNoChildren", "\\Junk"]},
                    {"INBOX.Archive", ".", ["\\HasNoChildren", "\\Archive"]}]
  end

  test "STATUS" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
            "* CAPABILITY (IMAPrev4)\r\n",
            "A001 OK test@example.com authenticated (Success)\r\n"])
      |> TestServer.on("A002 STATUS \"INBOX.Sent\" (MESSAGES RECENT UNSEEN)\r\n",    [
            "* STATUS \"INBOX.Sent\" (MESSAGES 4 RECENT 2 UNSEEN 3)\r\n",
            "A002 OK STATUS complete\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    {:ok, statuses} = IMAP.status(client, "INBOX.Sent", [:messages, :recent, :unseen])
    assert statuses == %{messages: 4, recent: 2, unseen: 3}
  end

  test "LOGOUT" do
    server = TestServer.start(ssl: true)
    TestServer.expect(server, fn(expectations) ->
      expectations
      |> TestServer.on(:connect,    "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
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
