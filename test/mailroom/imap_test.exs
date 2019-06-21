defmodule Mailroom.IMAPTest do
  use ExUnit.Case, async: true
  doctest Mailroom.IMAP

  alias Mailroom.{IMAP, TestServer}
  alias Mailroom.IMAP.Envelope
  alias Mailroom.IMAP.BodyStructure.Part

  @debug false

  test "STARTTLS" do
    server = TestServer.start(ssl: false)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK [CAPABILITY IMAPrev4 STARTTLS]\r\n")
      |> TestServer.on("A001 STARTTLS\r\n", ["A001 OK Begin TLS\r\n"], ssl: true)
      |> TestServer.on("A002 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A002 OK test@example.com authenticated (Success)\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: false,
               debug: @debug
             )

    assert IMAP.state(client) == :authenticated
  end

  test "LOGIN with invalid credentials" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"wrong\"\r\n", [
        "A001 NO [AUTHENTICATIONFAILED] Authentication failed\r\n"
      ])
      |> TestServer.on("A002 LOGOUT\r\n", ["* BYE Logging off now\r\n", "A002 OK We're done\r\n"])
    end)

    assert {:error, :authentication, "[AUTHENTICATIONFAILED] Authentication failed"} =
             IMAP.connect(server.address, "test@example.com", "wrong",
               port: server.port,
               ssl: true,
               debug: @debug
             )
  end

  test "LOGIN with interesting characters" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"p!@#$%^&*()\\\"\"\r\n", [
        "A001 NO [AUTHENTICATIONFAILED] Authentication failed\r\n"
      ])
      |> TestServer.on("A002 LOGOUT\r\n", ["* BYE Logging off now\r\n", "A002 OK We're done\r\n"])
    end)

    assert {:error, :authentication, "[AUTHENTICATIONFAILED] Authentication failed"} =
             IMAP.connect(server.address, "test@example.com", "p!@#$%^&*()\"",
               port: server.port,
               ssl: true,
               debug: @debug
             )
  end

  test "LOGIN" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    assert IMAP.state(client) == :authenticated
  end

  test "CAPABILITY request is issued if not supplied" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 CAPABILITY\r\n", [
        "* CAPABILITY IMAP4rev1 LITERAL+ ENABLE IDLE NAMESPACE UIDPLUS QUOTA\r\n",
        "A002 OK CAPABILITY complete\r\n"
      ])
    end)

    assert {:ok, _client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )
  end

  test "SELECT" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 4 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "* OK [UNSEEN 2]\r\n",
        "* OK [UIDVALIDITY 1474976037] UIDs valid\r\n",
        "* OK [UIDNEXT 5] Predicted next UID\r\n",
        "* OK [HIGHESTMODSEQ 2] Highest\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

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

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 CLOSE\r\n", ["A003 OK Closed\r\n"])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    client
    |> IMAP.select(:inbox)

    IMAP.close(client)
    assert IMAP.state(client) == :authenticated
    refute IMAP.mailbox(client)
  end

  test "EXAMINE" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 EXAMINE INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS ()] Read-only mailbox\r\n",
        "* 4 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "* OK [UNSEEN 2]\r\n",
        "* OK [UIDVALIDITY 1474976037] UIDs valid\r\n",
        "* OK [UIDNEXT 5] Predicted next UID\r\n",
        "* OK [HIGHESTMODSEQ 2] Highest\r\n",
        "A002 OK [READ-ONLY] examining INBOX. (Success)\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

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

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 LIST \"\" \"*\"\r\n", [
        "* LIST (\\HasChildren) \".\" INBOX\r\n",
        "* LIST (\\HasNoChildren \\Trash) \".\" INBOX.Trash\r\n",
        "* LIST (\\HasNoChildren \\Drafts) \".\" INBOX.Drafts\r\n",
        "* LIST (\\HasNoChildren \\Sent) \".\" INBOX.Sent\r\n",
        "* LIST (\\HasNoChildren \\Junk) \".\" INBOX.Junk\r\n",
        "* LIST (\\HasNoChildren \\Archive) \".\" \"INBOX.Archive\"\r\n",
        "A002 OK LIST complete\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    {:ok, list} = IMAP.list(client)

    assert list == [
             {"INBOX", ".", ["\\HasChildren"]},
             {"INBOX.Trash", ".", ["\\HasNoChildren", "\\Trash"]},
             {"INBOX.Drafts", ".", ["\\HasNoChildren", "\\Drafts"]},
             {"INBOX.Sent", ".", ["\\HasNoChildren", "\\Sent"]},
             {"INBOX.Junk", ".", ["\\HasNoChildren", "\\Junk"]},
             {"INBOX.Archive", ".", ["\\HasNoChildren", "\\Archive"]}
           ]
  end

  test "STATUS" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 STATUS \"INBOX.Sent\" (MESSAGES RECENT UNSEEN)\r\n", [
        "* STATUS \"INBOX.Sent\" (MESSAGES 4 RECENT 2 UNSEEN 3)\r\n",
        "A002 OK STATUS complete\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    {:ok, statuses} = IMAP.status(client, "INBOX.Sent", [:messages, :recent, :unseen])
    assert statuses == %{messages: 4, recent: 2, unseen: 3}
  end

  test "FETCH single message" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 FETCH 1 (UID)\r\n", ["* 1 FETCH (UID 46)\r\n", "A003 OK Success\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A004 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1, :uid)

    assert msgs == [{1, %{uid: 46}}]
    IMAP.logout(client)
  end

  test "SEARCH" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 SEARCH UNSEEN\r\n", ["* SEARCH 1 2 4 6 7\r\n", "A003 OK Success\r\n"])
      |> TestServer.on("A004 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A004 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.search("UNSEEN")

    assert msgs == [1, 2, 4, 6, 7]
    IMAP.logout(client)
  end

  test "SEARCH with enumerator function" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 SEARCH UNSEEN\r\n", ["* SEARCH 1 2 4 6 7\r\n", "A003 OK Success\r\n"])
      |> TestServer.on("A004 FETCH 1:2 (UID)\r\n", [
        "* 1 FETCH (UID 46)\r\n",
        "* 2 FETCH (UID 47)\r\n",
        "A004 OK Success\r\n"
      ])
      |> TestServer.on("A005 FETCH 4 (UID)\r\n", ["* 4 FETCH (UID 49)\r\n", "A005 OK Success\r\n"])
      |> TestServer.on("A006 FETCH 6:7 (UID)\r\n", [
        "* 6 FETCH (UID 51)\r\n",
        "* 7 FETCH (UID 52)\r\n",
        "A006 OK Success\r\n"
      ])
      |> TestServer.on("A007 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A007 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    client
    |> IMAP.select(:inbox)
    |> IMAP.search("UNSEEN", :uid, fn msg ->
      send(self(), msg)
    end)
    |> IMAP.logout()

    assert_received {1, %{uid: 46}}
    assert_received {2, %{uid: 47}}
    assert_received {4, %{uid: 49}}
    assert_received {6, %{uid: 51}}
    assert_received {7, %{uid: 52}}
  end

  test "FETCH request multiple items per message" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 FETCH 1 (UID FLAGS RFC822.SIZE)\r\n", [
        "* 1 FETCH (RFC822.SIZE 3325 INTERNALDATE \"26-Oct-2016 12:23:20 +0000\" FLAGS (\Seen))\r\n",
        "A003 OK Success\r\n"
      ])
      |> TestServer.on("A004 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A004 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1, [:uid, :flags, :rfc822_size])

    timestamp = IMAP.Utils.parse_timestamp("26-Oct-2016 12:23:20 +0000")

    assert msgs == [
             {1,
              %{
                flags: ["Seen"],
                internal_date: timestamp,
                rfc822_size: "3325"
              }}
           ]

    IMAP.logout(client)
  end

  test "FETCH multiple messages" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 FETCH 1:2 (UID)\r\n", [
        "* 1 FETCH (UID 46)\r\n",
        "* 2 FETCH (UID 47)\r\n",
        "A003 OK Success\r\n"
      ])
      |> TestServer.on("A004 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A004 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    client
    |> IMAP.select(:inbox)
    |> IMAP.fetch(1..2, :uid, fn msg ->
      send(self(), msg)
    end)
    |> IMAP.logout()

    assert_received {1, %{uid: 46}}
    assert_received {2, %{uid: 47}}
  end

  test "FETCH envelope" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 FETCH 1:2 (ENVELOPE)\r\n", [
        "* 1 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:23:14 +0200\" \"Test 1\" ((\"John Doe\" NIL \"john\" \"example.com\")) ((\"John Doe\" NIL \"john\" \"example.com\")) ((\"John Doe\" NIL \"john\" \"example.com\")) ((NIL NIL \"dev\" \"debtflow.co.za\")) NIL NIL NIL \"<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>\"))\r\n",
        "* 2 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:24:15 +0200\" \"Test 2\" ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((NIL NIL \"dev\" \"debtflow.co.za\")) NIL NIL \"652E7B61-60F6-421C-B954-4178BB769B27.example.com\" \"<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>\"))\r\n",
        "A003 OK Success\r\n"
      ])
      |> TestServer.on("A004 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A004 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1..2, :envelope)

    assert [
             {1,
              %{
                envelope: %Envelope{
                  date: {{2016, 10, 26}, {14, 23, 14}},
                  subject: "Test 1",
                  from: [
                    %{
                      name: "John Doe",
                      mailbox_name: "john",
                      host_name: "example.com",
                      email: "john@example.com"
                    }
                  ],
                  sender: [
                    %{
                      name: "John Doe",
                      mailbox_name: "john",
                      host_name: "example.com",
                      email: "john@example.com"
                    }
                  ],
                  reply_to: [
                    %{
                      name: "John Doe",
                      mailbox_name: "john",
                      host_name: "example.com",
                      email: "john@example.com"
                    }
                  ],
                  to: [
                    %{
                      name: nil,
                      mailbox_name: "dev",
                      host_name: "debtflow.co.za",
                      email: "dev@debtflow.co.za"
                    }
                  ],
                  cc: [],
                  bcc: [],
                  in_reply_to: nil,
                  message_id: "<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>"
                }
              }},
             {2,
              %{
                envelope: %Envelope{
                  date: {{2016, 10, 26}, {14, 24, 15}},
                  subject: "Test 2",
                  from: [
                    %{
                      name: "Jane Doe",
                      mailbox_name: "jane",
                      host_name: "example.com",
                      email: "jane@example.com"
                    }
                  ],
                  sender: [
                    %{
                      name: "Jane Doe",
                      mailbox_name: "jane",
                      host_name: "example.com",
                      email: "jane@example.com"
                    }
                  ],
                  reply_to: [
                    %{
                      name: "Jane Doe",
                      mailbox_name: "jane",
                      host_name: "example.com",
                      email: "jane@example.com"
                    }
                  ],
                  to: [
                    %{
                      name: nil,
                      mailbox_name: "dev",
                      host_name: "debtflow.co.za",
                      email: "dev@debtflow.co.za"
                    }
                  ],
                  cc: [],
                  bcc: [],
                  in_reply_to: "652E7B61-60F6-421C-B954-4178BB769B27.example.com",
                  message_id: "<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>"
                }
              }}
           ] = msgs

    IMAP.logout(client)
  end

  # FETCH result examples 2..10 from http://sgerwk.altervista.org/imapbodystructure.html
  test "FETCH BODYSTRUCTURE" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 FETCH 1:10 (BODYSTRUCTURE)\r\n", [
        "* 1 FETCH (BODYSTRUCTURE ((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"utf-8\") NIL NIL \"7BIT\" 438 9 NIL NIL NIL)(\"APPLICATION\" \"OCTET-STREAM\" (\"NAME\" \"Image.pdf\") NIL NIL \"BASE64\" 81800 NIL (\"ATTACHMENT\" (\"FILENAME\" \"Image.pdf\")) NIL) \"MIXED\" (\"BOUNDARY\" \"abcdfwefjsdvsdfg\") NIL NIL))\r\n",
        "* 2 FETCH (BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1315 42 NIL NIL NIL NIL))\r\n",
        "* 3 FETCH (BODYSTRUCTURE ((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 2234 63 NIL NIL NIL NIL)(\"TEXT\" \"HTML\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 2987 52 NIL NIL NIL NIL) \"ALTERNATIVE\" (\"BOUNDARY\" \"d3438gr7324\") NIL NIL NIL))\r\n",
        "* 4 FETCH (BODYSTRUCTURE ((\"TEXT\" \"HTML\" (\"CHARSET\" \"US-ASCII\") NIL NIL \"7BIT\" 119 2 NIL (\"INLINE\" NIL) NIL)(\"IMAGE\" \"JPEG\" (\"NAME\" \"4356415.jpg\") \"<0__=rhksjt>\" NIL \"BASE64\" 143804 NIL (\"INLINE\" (\"FILENAME\" \"4356415.jpg\")) NIL) \"RELATED\" (\"BOUNDARY\" \"0__=5tgd3d\") (\"INLINE\" NIL) NIL))\r\n",
        "* 5 FETCH (BODYSTRUCTURE ((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"ISO-8859-1\" \"FORMAT\" \"flowed\") NIL NIL \"QUOTED-PRINTABLE\" 2815 73 NIL NIL NIL NIL)((\"TEXT\" \"HTML\" (\"CHARSET\" \"ISO-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 4171 66 NIL NIL NIL NIL)(\"IMAGE\" \"JPEG\" (\"NAME\" \"image.jpg\") \"<3245dsf7435>\" NIL \"BASE64\" 189906 NIL NIL NIL NIL)(\"IMAGE\" \"GIF\" (\"NAME\" \"other.gif\") \"<32f6324f>\" NIL \"BASE64\" 1090 NIL NIL NIL NIL) \"RELATED\" (\"BOUNDARY\" \"--=sdgqgt\") NIL NIL NIL) \"ALTERNATIVE\" (\"BOUNDARY\" \"--=u5sfrj\") NIL NIL NIL))\r\n",
        "* 6 FETCH (BODYSTRUCTURE (((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"ISO-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 471 28 NIL NIL NIL)(\"TEXT\" \"HTML\" (\"CHARSET\" \"ISO-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1417 36 NIL (\"INLINE\" NIL) NIL) \"ALTERNATIVE\" (\"BOUNDARY\" \"1__=hqjksdm\") NIL NIL)(\"IMAGE\" \"GIF\" (\"NAME\" \"image.gif\") \"<1__=cxdf2f>\" NIL \"BASE64\" 50294 NIL (\"INLINE\" (\"FILENAME\" \"image.gif\")) NIL) \"RELATED\" (\"BOUNDARY\" \"0__=hqjksdm\") NIL NIL))\r\n",
        "* 7 FETCH (BODYSTRUCTURE ((\"TEXT\" \"HTML\" (\"CHARSET\" \"ISO-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 4692 69 NIL NIL NIL NIL)(\"APPLICATION\" \"PDF\" (\"NAME\" \"pages.pdf\") NIL NIL \"BASE64\" 38838 NIL (\"attachment\" (\"FILENAME\" \"pages.pdf\")) NIL NIL) \"MIXED\" (\"BOUNDARY\" \"----=6fgshr\") NIL NIL NIL))\r\n",
        "* 8 FETCH (BODYSTRUCTURE (((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"QUOTED-PRINTABLE\" 403 6 NIL NIL NIL NIL)(\"TEXT\" \"HTML\" (\"CHARSET\" \"UTF-8\") NIL NIL \"QUOTED-PRINTABLE\" 421 6 NIL NIL NIL NIL) \"ALTERNATIVE\" (\"BOUNDARY\" \"----=fghgf3\") NIL NIL NIL)(\"APPLICATION\" \"MSWORD\" (\"NAME\" \"letter.doc\") NIL NIL \"BASE64\" 110000 NIL (\"attachment\" (\"FILENAME\" \"letter.doc\" \"SIZE\" \"80384\")) NIL NIL) \"MIXED\" (\"BOUNDARY\" \"----=y34fgl\") NIL NIL NIL))\r\n",
        "* 9 FETCH (BODYSTRUCTURE ((((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"ISO-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 833 30 NIL NIL NIL)(\"TEXT\" \"HTML\" (\"CHARSET\" \"ISO-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 3412 62 NIL (\"INLINE\" NIL) NIL) \"ALTERNATIVE\" (\"BOUNDARY\" \"2__=fgrths\") NIL NIL)(\"IMAGE\" \"GIF\" (\"NAME\" \"485039.gif\") \"<2__=lgkfjr>\" NIL \"BASE64\" 64 NIL (\"INLINE\" (\"FILENAME\" \"485039.gif\")) NIL) \"RELATED\" (\"BOUNDARY\" \"1__=fgrths\") NIL NIL)(\"APPLICATION\" \"PDF\" (\"NAME\" \"title.pdf\") \"<1__=lgkfjr>\" NIL \"BASE64\" 333980 NIL (\"ATTACHMENT\" (\"FILENAME\" \"title.pdf\")) NIL) \"MIXED\" (\"BOUNDARY\" \"0__=fgrths\") NIL NIL))\r\n",
        "* 10 FETCH (BODYSTRUCTURE ((\"TEXT\" \"HTML\" NIL NIL NIL \"7BIT\" 151 0 NIL NIL NIL) \"MIXED\" (\"BOUNDARY\" \"----=rfsewr\") NIL NIL))\r\n",
        "A003 OK Success\r\n"
      ])
      |> TestServer.on("A004 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A004 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1..10, :body_structure)

    IMAP.logout(client)

    assert [
             {1,
              %{
                body_structure: %{
                  multipart: true,
                  type: "mixed",
                  params: %{},
                  parts: [
                    %{
                      section: "1",
                      type: "text/plain",
                      params: %{"charset" => "utf-8"}
                    },
                    %{
                      section: "2",
                      type: "application/octet-stream",
                      params: %{"name" => "Image.pdf"},
                      disposition: "attachment",
                      file_name: "Image.pdf"
                    }
                  ]
                }
              }},
             {2,
              %{
                body_structure: %Part{
                  multipart: false,
                  params: %{"charset" => "iso-8859-1"},
                  parts: [],
                  type: "text/plain"
                }
              }},
             {3,
              %{
                body_structure: %Part{
                  multipart: true,
                  params: %{},
                  parts: [
                    %Part{
                      multipart: false,
                      params: %{"charset" => "iso-8859-1"},
                      parts: [],
                      section: "1",
                      type: "text/plain"
                    },
                    %Part{
                      multipart: false,
                      params: %{"charset" => "iso-8859-1"},
                      parts: [],
                      section: "2",
                      type: "text/html"
                    }
                  ],
                  type: "alternative"
                }
              }},
             {4,
              %{
                body_structure: %Part{
                  multipart: true,
                  params: %{},
                  parts: [
                    %Part{
                      multipart: false,
                      params: %{"charset" => "US-ASCII"},
                      parts: [],
                      section: "1",
                      type: "text/html"
                    },
                    %Part{
                      multipart: false,
                      params: %{"name" => "4356415.jpg"},
                      parts: [],
                      section: "2",
                      type: "image/jpeg"
                    }
                  ],
                  type: "related"
                }
              }},
             {5,
              %{
                body_structure: %Part{
                  multipart: true,
                  params: %{},
                  parts: [
                    %Part{
                      multipart: false,
                      params: %{
                        "charset" => "ISO-8859-1",
                        "format" => "flowed"
                      },
                      parts: [],
                      section: "1",
                      type: "text/plain"
                    },
                    %Part{
                      multipart: true,
                      params: %{},
                      parts: [
                        %Part{
                          multipart: false,
                          params: %{"charset" => "ISO-8859-1"},
                          parts: [],
                          section: "2.1",
                          type: "text/html"
                        },
                        %Part{
                          multipart: false,
                          params: %{"name" => "image.jpg"},
                          parts: [],
                          section: "2.2",
                          type: "image/jpeg"
                        },
                        %Part{
                          multipart: false,
                          params: %{"name" => "other.gif"},
                          parts: [],
                          section: "2.3",
                          type: "image/gif"
                        }
                      ],
                      section: "2",
                      type: "related"
                    }
                  ],
                  type: "alternative"
                }
              }},
             {6,
              %{
                body_structure: %Part{
                  multipart: true,
                  params: %{},
                  parts: [
                    %Part{
                      multipart: true,
                      params: %{},
                      parts: [
                        %Part{
                          multipart: false,
                          params: %{"charset" => "ISO-8859-1"},
                          parts: [],
                          section: "1.1",
                          type: "text/plain"
                        },
                        %Part{
                          multipart: false,
                          params: %{"charset" => "ISO-8859-1"},
                          parts: [],
                          section: "1.2",
                          type: "text/html"
                        }
                      ],
                      section: "1",
                      type: "alternative"
                    },
                    %Part{
                      multipart: false,
                      params: %{"name" => "image.gif"},
                      parts: [],
                      section: "2",
                      type: "image/gif"
                    }
                  ],
                  type: "related"
                }
              }},
             {7,
              %{
                body_structure: %Part{
                  multipart: true,
                  params: %{},
                  parts: [
                    %Part{
                      multipart: false,
                      params: %{"charset" => "ISO-8859-1"},
                      parts: [],
                      section: "1",
                      type: "text/html"
                    },
                    %Part{
                      multipart: false,
                      params: %{"name" => "pages.pdf"},
                      parts: [],
                      section: "2",
                      type: "application/pdf"
                    }
                  ],
                  type: "mixed"
                }
              }},
             {8,
              %{
                body_structure: %Part{
                  multipart: true,
                  params: %{},
                  parts: [
                    %Part{
                      multipart: true,
                      params: %{},
                      parts: [
                        %Part{
                          multipart: false,
                          params: %{"charset" => "UTF-8"},
                          parts: [],
                          section: "1.1",
                          type: "text/plain"
                        },
                        %Part{
                          multipart: false,
                          params: %{"charset" => "UTF-8"},
                          parts: [],
                          section: "1.2",
                          type: "text/html"
                        }
                      ],
                      section: "1",
                      type: "alternative"
                    },
                    %Part{
                      multipart: false,
                      params: %{"name" => "letter.doc"},
                      parts: [],
                      section: "2",
                      type: "application/msword"
                    }
                  ],
                  type: "mixed"
                }
              }},
             {9,
              %{
                body_structure: %Part{
                  multipart: true,
                  params: %{},
                  parts: [
                    %Part{
                      multipart: true,
                      params: %{},
                      parts: [
                        %Part{
                          multipart: true,
                          params: %{},
                          parts: [
                            %Part{
                              multipart: false,
                              params: %{"charset" => "ISO-8859-1"},
                              parts: [],
                              section: "1.1.1",
                              type: "text/plain"
                            },
                            %Part{
                              multipart: false,
                              params: %{"charset" => "ISO-8859-1"},
                              parts: [],
                              section: "1.1.2",
                              type: "text/html"
                            }
                          ],
                          section: "1.1",
                          type: "alternative"
                        },
                        %Part{
                          multipart: false,
                          params: %{"name" => "485039.gif"},
                          parts: [],
                          section: "1.2",
                          type: "image/gif"
                        }
                      ],
                      section: "1",
                      type: "related"
                    },
                    %Part{
                      multipart: false,
                      params: %{"name" => "title.pdf"},
                      parts: [],
                      section: "2",
                      type: "application/pdf"
                    }
                  ],
                  type: "mixed"
                }
              }},
             {10,
              %{
                body_structure: %Part{
                  multipart: true,
                  params: %{},
                  parts: [
                    %Part{
                      multipart: false,
                      params: %{},
                      parts: [],
                      section: "1",
                      type: "text/html"
                    }
                  ],
                  type: "mixed"
                }
              }}
           ] = msgs
  end

  test "FETCH body text" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 FETCH 1 (BODY[TEXT])\r\n", [
        "* 1 FETCH (BODY[TEXT] {8}\r\nTest 1\r\n)\r\n",
        "A003 OK Success\r\n"
      ])
      |> TestServer.on("A004 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A004 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    {:ok, msgs} =
      client
      |> IMAP.select(:inbox)
      |> IMAP.fetch(1, "BODY[TEXT]")

    assert msgs == [{1, %{"BODY[TEXT]" => "Test 1\r\n"}}]
    IMAP.logout(client)
  end

  test "STORE" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 STORE 1 -FLAGS (\\Seen)\r\n", [
        "* 1 FETCH (FLAGS ())\r\n",
        "A003 OK Success\r\n"
      ])
      |> TestServer.on("A004 STORE 1 +FLAGS (\\Answered)\r\n", [
        "* 1 FETCH (FLAGS (\\Answered))\r\n",
        "A004 OK Success\r\n"
      ])
      |> TestServer.on("A005 STORE 1:2 FLAGS.SILENT (\\Deleted)\r\n", ["A005 OK Success\r\n"])
      |> TestServer.on("A006 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A006 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    client
    |> IMAP.select(:inbox)
    |> IMAP.remove_flags(1, [:seen])
    |> IMAP.add_flags(1, [:answered])
    |> IMAP.set_flags(1..2, [:deleted], silent: true)

    IMAP.logout(client)
  end

  test "COPY" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 COPY 1:2 \"Archive\"\r\n", [
        "* 1 FETCH (FLAGS (\\Seen))\r\n",
        "* 2 FETCH (FLAGS (\\Seen))\r\n",
        "A003 OK Copy completed\r\n"
      ])
      |> TestServer.on("A004 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A004 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    client
    |> IMAP.select(:inbox)
    |> IMAP.copy(1..2, "Archive")

    IMAP.logout(client)
  end

  test "EXPUNGE" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 STORE 1:2 +FLAGS (\\Deleted)\r\n", [
        "* 1 FETCH (FLAGS (\\Deleted))\r\n",
        "* 2 FETCH (FLAGS (\\Deleted))\r\n",
        "A003 OK Store completed\r\n"
      ])
      |> TestServer.on("A004 EXPUNGE\r\n", [
        "* 1 EXPUNGE\r\n",
        "* 1 EXPUNGE\r\n",
        "A004 OK Expunge completed\r\n"
      ])
      |> TestServer.on("A005 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A005 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    client
    |> IMAP.select(:inbox)
    |> IMAP.add_flags(1..2, [:deleted])
    |> IMAP.expunge()

    IMAP.logout(client)
  end

  test "IDLE" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4 IDLE)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 0 EXISTS\r\n",
        "* 0 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.on("DONE\r\n", [
        "A003 OK IDLE terminated\r\n"
      ])
      |> TestServer.on("A004 IDLE\r\n", [
        "+ idling\r\n",
        "* 2 EXISTS\r\n"
      ])
      |> TestServer.on("DONE\r\n", [
        "A004 OK IDLE terminated\r\n"
      ])
      |> TestServer.on("A005 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A005 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    client
    |> IMAP.select(:inbox)
    |> IMAP.idle(timeout: 100)
    |> IMAP.idle()

    IMAP.logout(client)
  end

  test "LOGOUT" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.on(:connect, "* OK IMAP ready\r\n")
      |> TestServer.on("A001 LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "A001 OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.on("A002 SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 2 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A003 OK Logged out\r\n"
      ])
    end)

    assert {:ok, client} =
             IMAP.connect(server.address, "test@example.com", "P@55w0rD",
               port: server.port,
               ssl: true,
               debug: @debug
             )

    client
    |> IMAP.select(:inbox)

    IMAP.logout(client)
    assert IMAP.state(client) == :logged_out
  end
end
