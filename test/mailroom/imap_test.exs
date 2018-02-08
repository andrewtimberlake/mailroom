defmodule Mailroom.IMAPTest do
  use ExUnit.Case, async: true
  doctest Mailroom.IMAP

  alias Mailroom.{IMAP,TestServer,Envelope}

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

    assert {:ok, _client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
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

  test "FETCH single message" do
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
      |> TestServer.on("A003 FETCH 1 (UID)\r\n", [
            "* 1 FETCH (UID 46)\r\n",
            "A003 OK Success\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A004 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1, :uid)
    assert msgs == [{1, %{uid: 46}}]
    IMAP.logout(client)
  end

  test "SEARCH" do
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
      |> TestServer.on("A003 SEARCH UNSEEN\r\n", [
            "* SEARCH 1 2 4 6 7\r\n",
            "A003 OK Success\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A004 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.search("UNSEEN")
    assert msgs == [1, 2, 4, 6, 7]
    IMAP.logout(client)
  end

  test "SEARCH with enumerator function" do
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
      |> TestServer.on("A003 SEARCH UNSEEN\r\n", [
            "* SEARCH 1 2 4 6 7\r\n",
            "A003 OK Success\r\n"])
      |> TestServer.on("A004 FETCH 1:2 (UID)\r\n", [
            "* 1 FETCH (UID 46)\r\n",
            "* 2 FETCH (UID 47)\r\n",
            "A004 OK Success\r\n"])
      |> TestServer.on("A005 FETCH 4 (UID)\r\n", [
            "* 4 FETCH (UID 49)\r\n",
            "A005 OK Success\r\n"])
      |> TestServer.on("A006 FETCH 6:7 (UID)\r\n", [
            "* 6 FETCH (UID 51)\r\n",
            "* 7 FETCH (UID 52)\r\n",
            "A006 OK Success\r\n"])
      |> TestServer.on("A007 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A007 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    |> IMAP.search("UNSEEN", :uid, fn(msg) ->
      send self(), msg
    end)
    |> IMAP.logout

    assert_received {1, %{uid: 46}}
    assert_received {2, %{uid: 47}}
    assert_received {4, %{uid: 49}}
    assert_received {6, %{uid: 51}}
    assert_received {7, %{uid: 52}}
  end

  test "FETCH request multiple items per message" do
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
      |> TestServer.on("A003 FETCH 1 (UID FLAGS RFC822.SIZE)\r\n", [
            "* 1 FETCH (RFC822.SIZE 3325 INTERNALDATE \"26-Oct-2016 12:23:20 +0000\" FLAGS (\Seen))\r\n",
            "A003 OK Success\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A004 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1, [:uid, :flags, :rfc822_size])

    assert msgs == [{1, %{flags: ["Seen"],
                          internal_date: Timex.parse!("26-Oct-2016 12:23:20 +0000", "{D}-{Mshort}-{YYYY} {h24}:{m}:{s} {Z}"),
                          rfc822_size: "3325"}}]
    IMAP.logout(client)
  end

  test "FETCH multiple messages" do
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
      |> TestServer.on("A003 FETCH 1:2 (UID)\r\n", [
            "* 1 FETCH (UID 46)\r\n",
            "* 2 FETCH (UID 47)\r\n",
            "A003 OK Success\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A004 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    |> IMAP.fetch(1..2, :uid, fn(msg) ->
      send self(), msg
    end)
    |> IMAP.logout

    assert_received {1, %{uid: 46}}
    assert_received {2, %{uid: 47}}
  end

  test "FETCH envelope" do
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
      |> TestServer.on("A003 FETCH 1 (ENVELOPE)\r\n", [
            "* 1 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:23:14 +0200\" \"Test 1\" ((\"John Doe\" NIL \"john\" \"example.com\")) ((\"John Doe\" NIL \"john\" \"example.com\")) ((\"John Doe\" NIL \"john\" \"example.com\")) ((NIL NIL \"dev\" \"debtflow.co.za\")) NIL NIL NIL \"<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>\"))\r\n",
            "A003 OK Success\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A004 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1, :envelope)

    assert msgs == [{1, %{envelope: %Envelope{date: Timex.parse!("Wed, 26 Oct 2016 14:23:14 +0200", "{RFC822}"),
                                              subject: "Test 1",
                                              from: [{"John Doe", "john", "example.com"}],
                                              sender: [{"John Doe", "john", "example.com"}],
                                              reply_to: [{"John Doe", "john", "example.com"}],
                                              to: [{nil, "dev", "debtflow.co.za"}],
                                              cc: [],
                                              bcc: [],
                                              in_reply_to: [],
                                              message_id: "<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>"}}}]
    IMAP.logout(client)
  end

  test "FETCH body" do
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
      |> TestServer.on("A003 FETCH 1 (BODY[TEXT])\r\n", [
            "* 1 FETCH (BODY[TEXT] {8}\r\nTest 1\r\n)\r\n",
            "A003 OK Success\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A004 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1, "BODY[TEXT]")

    assert msgs == [{1, %{"BODY[TEXT]" => "Test 1\r\n"}}]
    IMAP.logout(client)
  end

  test "STORE" do
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
      |> TestServer.on("A003 STORE 1 -FLAGS (\\Seen)\r\n", [
            "* 1 FETCH (FLAGS ())\r\n",
            "A003 OK Success\r\n"])
      |> TestServer.on("A004 STORE 1 +FLAGS (\\Answered)\r\n", [
            "* 1 FETCH (FLAGS (\\Answered))\r\n",
            "A004 OK Success\r\n"])
      |> TestServer.on("A005 STORE 1:2 FLAGS.SILENT (\\Deleted)\r\n", [
            "A005 OK Success\r\n"])
      |> TestServer.on("A006 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A006 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    |> IMAP.remove_flags(1, [:seen])
    |> IMAP.add_flags(1, [:answered])
    |> IMAP.set_flags(1..2, [:deleted], silent: true)

    IMAP.logout(client)
  end

  test "COPY" do
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
      |> TestServer.on("A003 COPY 1:2 \"Archive\"\r\n", [
            "* 1 FETCH (FLAGS (\\Seen))\r\n",
            "* 2 FETCH (FLAGS (\\Seen))\r\n",
            "A003 OK Copy completed\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A004 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    |> IMAP.copy(1..2, "Archive")

    IMAP.logout(client)
  end

  test "EXPUNGE" do
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
      |> TestServer.on("A003 STORE 1:2 +FLAGS (\\Deleted)\r\n", [
            "* 1 FETCH (FLAGS (\\Deleted))\r\n",
            "* 2 FETCH (FLAGS (\\Deleted))\r\n",
            "A003 OK Store completed\r\n"])
      |> TestServer.on("A004 EXPUNGE\r\n", [
            "* 1 EXPUNGE\r\n",
            "* 1 EXPUNGE\r\n",
            "A004 OK Expunge completed\r\n"])
      |> TestServer.on("A005 LOGOUT\r\n", [
            "* BYE We're out of here\r\n",
            "A005 OK Logged out\r\n"])
    end)

    assert {:ok, client} = IMAP.connect(server.address, "test@example.com", "P@55w0rD", port: server.port, ssl: true, debug: @debug)
    client
    |> IMAP.select(:inbox)
    |> IMAP.add_flags(1..2, [:deleted])
    |> IMAP.expunge

    IMAP.logout(client)
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
