defmodule Mailroom.InboxTest do
  use ExUnit.Case, async: true

  alias Mailroom.TestServer

  @debug false

  defmodule TestMailProcessor do
    def match_subject_regex(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_subject_regex, msg_id})
      :delete
    end

    def match_subject_string(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_subject_string, msg_id})
      :delete
    end

    def match_has_attachment(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_has_attachment, msg_id})
      :delete
    end

    def match_and_fetch(%{id: msg_id, mail: mail, message: message, assigns: %{test_pid: pid}}) do
      send(pid, {:match_and_fetch, msg_id, mail, message})
      :delete
    end

    def match_header(%{id: msg_id, mail: nil, message: nil, assigns: %{test_pid: pid}}) do
      send(pid, {:match_header, msg_id})
      :delete
    end

    def match_all(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:match_all, msg_id})
      :delete
    end
  end

  defmodule TestMailRouter do
    use Mailroom.Inbox

    def config(opts) do
      Keyword.merge(opts, username: "test@example.com", password: "P@55w0rD")
    end

    match do
      recipient(~r/(john|jane)@example.com/)

      process(:match_to)
    end

    match do
      to("ignore@example.com")

      ignore
    end

    match do
      subject(~r/test \d+/i)

      process(TestMailProcessor, :match_subject_regex)
    end

    match do
      subject("Testing 3")

      process(TestMailProcessor, :match_subject_string)
    end

    match do
      subject("To be fetched")

      fetch_mail
      process(TestMailProcessor, :match_and_fetch)
    end

    match do
      has_attachment?

      process(TestMailProcessor, :match_has_attachment)
    end

    match do
      all

      process(TestMailProcessor, :match_all)
    end

    def match_to(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_to, msg_id})
      :delete
    end
  end

  defmodule TestMailHeaderRouter do
    use Mailroom.Inbox

    def config(opts) do
      Keyword.merge(opts, username: "test@example.com", password: "P@55w0rD")
    end

    match do
      header("In-Reply-To", ~r/message-id/)

      process(TestMailProcessor, :match_header)
    end

    match do
      all

      process(TestMailProcessor, :match_all)
    end

    def match_to(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_to, msg_id})
      :delete
    end
  end

  test "Can match on any TO" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.tagged(:connect, "* OK IMAP ready\r\n")
      |> TestServer.tagged("LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.tagged("SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 0 EXISTS\r\n",
        "* 0 RECENT\r\n",
        "OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.tagged("IDLE\r\n", [
        "+ idling\r\n",
        "* 3 EXISTS\r\n"
      ])
      |> TestServer.tagged("DONE\r\n", [
        "OK IDLE terminated\r\n"
      ])
      |> TestServer.tagged("SEARCH UNSEEN\r\n", [
        "* SEARCH 1 2 3\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("FETCH 1:3 (ENVELOPE BODYSTRUCTURE)\r\n", [
        "* 1 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:23:14 +0200\" \"The subject\" ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"John Doe\" NIL \"john\" \"example.com\")) NIL NIL NIL \"<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>\") BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1315 42 NIL NIL NIL NIL))\r\n",
        "* 2 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:23:14 +0200\" \"The subject\" ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Jane Doe\" NIL \"JANE\" \"EXAMPLE.COM\")) NIL NIL NIL \"<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>\") BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1315 42 NIL NIL NIL NIL))\r\n",
        "* 3 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:24:15 +0200\" \"The subject\" ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((NIL NIL \"george\" \"example.com\")) NIL NIL \"652E7B61-60F6-421C-B954-4178BB769B27.example.com\" \"<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>\") BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1315 42 NIL NIL NIL NIL))\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("STORE 1 +FLAGS (\\Deleted)\r\n", [
        "* 1 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("STORE 2 +FLAGS (\\Deleted)\r\n", [
        "* 2 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("STORE 3 +FLAGS (\\Deleted)\r\n", [
        "* 3 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("EXPUNGE\r\n", [
        "* 1 EXPUNGE\r\n",
        "* 2 EXPUNGE\r\n",
        "* 3 EXPUNGE\r\n",
        "OK Expunge completed\r\n"
      ])
      |> TestServer.tagged("IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.tagged("DONE\r\n", [
        "OK IDLE terminated\r\n"
      ])
      |> TestServer.tagged("LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "OK Logged out\r\n"
      ])
    end)

    ExUnit.CaptureLog.capture_log(fn ->
      {:ok, pid} =
        TestMailRouter.start_link(
          server: server.address,
          port: server.port,
          ssl: true,
          assigns: %{test_pid: self()},
          debug: @debug
        )

      assert_receive({:matched_to, 1})
      assert_receive({:matched_to, 2})
      refute_receive({:matched_to, _})
      TestMailRouter.close(pid)
    end)
  end

  test "Can match on a subject" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.tagged(:connect, "* OK IMAP ready\r\n")
      |> TestServer.tagged("LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.tagged("SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 0 EXISTS\r\n",
        "* 0 RECENT\r\n",
        "OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.tagged("IDLE\r\n", [
        "+ idling\r\n",
        "* 3 EXISTS\r\n"
      ])
      |> TestServer.tagged("DONE\r\n", [
        "OK IDLE terminated\r\n"
      ])
      |> TestServer.tagged("SEARCH UNSEEN\r\n", [
        "* SEARCH 1 2 3\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("FETCH 1:3 (ENVELOPE BODYSTRUCTURE)\r\n", [
        "* 1 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:23:14 +0200\" \"First one\" ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"John Doe\" NIL \"bruce\" \"example.com\")) NIL NIL NIL \"<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>\") BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1315 42 NIL NIL NIL NIL))\r\n",
        "* 2 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:24:15 +0200\" \"Test 2\" ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((NIL NIL \"george\" \"example.com\")) NIL NIL \"652E7B61-60F6-421C-B954-4178BB769B27.example.com\" \"<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>\") BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1315 42 NIL NIL NIL NIL))\r\n",
        "* 3 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:24:15 +0200\" \"Testing 3\" ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((NIL NIL \"george\" \"example.com\")) NIL NIL \"652E7B61-60F6-421C-B954-4178BB769B27.example.com\" \"<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>\") BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1315 42 NIL NIL NIL NIL))\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("STORE 1 +FLAGS (\\Deleted)\r\n", [
        "* 1 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("STORE 2 +FLAGS (\\Deleted)\r\n", [
        "* 2 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("STORE 3 +FLAGS (\\Deleted)\r\n", [
        "* 3 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("EXPUNGE\r\n", [
        "* 2 EXPUNGE\r\n",
        "* 3 EXPUNGE\r\n",
        "OK Expunge completed\r\n"
      ])
      |> TestServer.tagged("IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.tagged("DONE\r\n", [
        "OK IDLE terminated\r\n"
      ])
      |> TestServer.tagged("LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "OK Logged out\r\n"
      ])
    end)

    ExUnit.CaptureLog.capture_log(fn ->
      {:ok, pid} =
        TestMailRouter.start_link(
          server: server.address,
          port: server.port,
          ssl: true,
          assigns: %{test_pid: self()},
          debug: @debug
        )

      assert_receive({:matched_subject_regex, 2})
      assert_receive({:matched_subject_string, 3})
      assert_receive({:match_all, 1})
      refute_receive({:matched_to, _})
      TestMailRouter.close(pid)
    end)
  end

  test "Can match on an having an attachment" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.tagged(:connect, "* OK IMAP ready\r\n")
      |> TestServer.tagged("LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.tagged("SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 3 EXISTS\r\n",
        "* 0 RECENT\r\n",
        "OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.tagged("SEARCH UNSEEN\r\n", [
        "* SEARCH 1 2 3\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("FETCH 1:3 (ENVELOPE BODYSTRUCTURE)\r\n", [
        ~s[* 1 FETCH (ENVELOPE ("Mon, 10 Jun 2019 11:57:36 +0200" "Attached." (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) ((NIL NIL "george" "example.com")) NIL NIL "<f69b912d-310b-4133-b526-07f715242db6@Spark>" "<4cff0831-67f5-4457-b60a-3331ba893348@Spark>") BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 8 1 NIL ("INLINE" NIL) NIL)(("TEXT" "HTML" ("CHARSET" "utf-8") NIL NIL "QUOTED-PRINTABLE" 293 6 NIL ("INLINE" NIL) NIL)("IMAGE" "PNG" NIL "<D0C5BB9CBFAE48E09727D1A67721F939>" NIL "BASE64" 3934 NIL ("INLINE" ("FILENAME" "3M-Logo.png")) NIL) "RELATED" ("BOUNDARY" "5cfe29a0_507ed7ab_d312") NIL NIL) "ALTERNATIVE" ("BOUNDARY" "5cfe29a0_2eb141f2_d312") NIL NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 2730568 NIL ("ATTACHMENT" ("FILENAME" "test.pdf")) NIL) "MIXED" ("BOUNDARY" "5cfe29a0_41b71efb_d312") NIL NIL))\r\n],
        ~s[* 2 FETCH (ENVELOPE ("Tue, 11 Jun 2019 09:21:23 +0200" "Test with multiple attachments" (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) ((NIL NIL "george" "example.com")) NIL NIL "<60f5c212-a3a0-464d-b287-6d81f46a1359@Spark>" "<ada126ec-8244-4abd-b3bf-a793d456fd4e@Spark>") BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 9 1 NIL ("INLINE" NIL) NIL)("TEXT" "HTML" ("CHARSET" "utf-8") NIL NIL "QUOTED-PRINTABLE" 195 4 NIL ("INLINE" NIL) NIL) "ALTERNATIVE" ("BOUNDARY" "5cff5678_ded7263_d312") NIL NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 2 NIL ("ATTACHMENT" ("FILENAME" "test.csv")) NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 14348938 NIL ("ATTACHMENT" ("FILENAME" "test.doc")) NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 240 NIL ("ATTACHMENT" ("FILENAME" "test.mid")) NIL)("TEXT" "PLAIN" NIL NIL NIL "BASE64" 10 1 NIL ("ATTACHMENT" ("FILENAME" "test.txt")) NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 974 NIL ("ATTACHMENT" ("FILENAME" "test.wav")) NIL) "MIXED" ("BOUNDARY" "5cff5678_7fdcc233_d312") NIL NIL))\r\n],
        "* 3 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:24:15 +0200\" \"Another one\" ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((NIL NIL \"george\" \"example.com\")) NIL NIL \"652E7B61-60F6-421C-B954-4178BB769B27.example.com\" \"<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>\") BODYSTRUCTURE  (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 1315 42 NIL NIL NIL NIL))\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("STORE 1 +FLAGS (\\Deleted)\r\n", [
        "* 1 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("STORE 2 +FLAGS (\\Deleted)\r\n", [
        "* 2 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("STORE 3 +FLAGS (\\Deleted)\r\n", [
        "* 2 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("EXPUNGE\r\n", [
        "* 1 EXPUNGE\r\n",
        "* 2 EXPUNGE\r\n",
        "* 3 EXPUNGE\r\n",
        "OK Expunge completed\r\n"
      ])
      |> TestServer.tagged("IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.tagged("DONE\r\n", [
        "OK IDLE terminated\r\n"
      ])
      |> TestServer.tagged("LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "OK Logged out\r\n"
      ])
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, pid} =
          TestMailRouter.start_link(
            server: server.address,
            port: server.port,
            ssl: true,
            assigns: %{test_pid: self()},
            debug: @debug
          )

        assert_receive({:matched_has_attachment, 1})
        assert_receive({:matched_has_attachment, 2})
        assert_receive({:match_all, 3})
        TestMailRouter.close(pid)
      end)

    assert log =~ "Processing 3 emails"

    assert log =~
             "Processing msg:1 TO:george@example.com FROM:andrew@internuity.net SUBJECT:\"Attached.\" using Mailroom.InboxTest.TestMailProcessor#match_has_attachment -> :delete"

    assert log =~
             "Processing msg:2 TO:george@example.com FROM:andrew@internuity.net SUBJECT:\"Test with multiple attachments\" using Mailroom.InboxTest.TestMailProcessor#match_has_attachment -> :delete"

    assert log =~
             "Processing msg:3 TO:george@example.com FROM:jane@example.com SUBJECT:\"Another one\" using Mailroom.InboxTest.TestMailProcessor#match_all -> :delete"
  end

  test "ignore an email" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.tagged(:connect, "* OK IMAP ready\r\n")
      |> TestServer.tagged("LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.tagged("SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 1 EXISTS\r\n",
        "* 1 RECENT\r\n",
        "OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.tagged("SEARCH UNSEEN\r\n", [
        "* SEARCH 1\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("FETCH 1 (ENVELOPE BODYSTRUCTURE)\r\n", [
        ~s[* 1 FETCH (ENVELOPE ("Mon, 10 Jun 2019 11:57:36 +0200" "Attached." (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) ((NIL NIL "ignore" "example.com")) NIL NIL "<f69b912d-310b-4133-b526-07f715242db6@Spark>" "<4cff0831-67f5-4457-b60a-3331ba893348@Spark>") BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 8 1 NIL ("INLINE" NIL) NIL)(("TEXT" "HTML" ("CHARSET" "utf-8") NIL NIL "QUOTED-PRINTABLE" 293 6 NIL ("INLINE" NIL) NIL)("IMAGE" "PNG" NIL "<D0C5BB9CBFAE48E09727D1A67721F939>" NIL "BASE64" 3934 NIL ("INLINE" ("FILENAME" "3M-Logo.png")) NIL) "RELATED" ("BOUNDARY" "5cfe29a0_507ed7ab_d312") NIL NIL) "ALTERNATIVE" ("BOUNDARY" "5cfe29a0_2eb141f2_d312") NIL NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 2730568 NIL ("ATTACHMENT" ("FILENAME" "test.pdf")) NIL) "MIXED" ("BOUNDARY" "5cfe29a0_41b71efb_d312") NIL NIL))\r\n],
        "OK Success\r\n"
      ])
      |> TestServer.tagged("STORE 1 +FLAGS (\\Deleted)\r\n", [
        "* 1 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("EXPUNGE\r\n", [
        "* 1 EXPUNGE\r\n",
        "OK Expunge completed\r\n"
      ])
      |> TestServer.tagged("IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.tagged("DONE\r\n", [
        "OK IDLE terminated\r\n"
      ])
      |> TestServer.tagged("LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "OK Logged out\r\n"
      ])
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, pid} =
          TestMailRouter.start_link(
            server: server.address,
            port: server.port,
            ssl: true,
            assigns: %{test_pid: self()},
            debug: @debug
          )

        # refute_received _
        TestMailRouter.close(pid)
      end)

    assert log =~ "Processing 1 emails"

    assert log =~
             "Processing msg:1 TO:ignore@example.com FROM:andrew@internuity.net SUBJECT:\"Attached.\" -> :ignore"
  end

  test "Fetch email in handler" do
    server = TestServer.start(ssl: true)

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.tagged(:connect, "* OK IMAP ready\r\n")
      |> TestServer.tagged("LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.tagged("SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 1 EXISTS\r\n",
        "* 0 RECENT\r\n",
        "OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.tagged("SEARCH UNSEEN\r\n", [
        "* SEARCH 1\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("FETCH 1 (ENVELOPE BODYSTRUCTURE)\r\n", [
        ~s[* 1 FETCH (ENVELOPE ("Mon, 10 Jun 2019 11:57:36 +0200" "To be fetched" (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) ((NIL NIL "george" "example.com")) NIL NIL "<f69b912d-310b-4133-b526-07f715242db6@Spark>" "<4cff0831-67f5-4457-b60a-3331ba893348@Spark>") BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 8 1 NIL ("INLINE" NIL) NIL)(("TEXT" "HTML" ("CHARSET" "utf-8") NIL NIL "QUOTED-PRINTABLE" 293 6 NIL ("INLINE" NIL) NIL)("IMAGE" "PNG" NIL "<D0C5BB9CBFAE48E09727D1A67721F939>" NIL "BASE64" 3934 NIL ("INLINE" ("FILENAME" "3M-Logo.png")) NIL) "RELATED" ("BOUNDARY" "5cfe29a0_507ed7ab_d312") NIL NIL) "ALTERNATIVE" ("BOUNDARY" "5cfe29a0_2eb141f2_d312") NIL NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 2730568 NIL ("ATTACHMENT" ("FILENAME" "test.pdf")) NIL) "MIXED" ("BOUNDARY" "5cfe29a0_41b71efb_d312") NIL NIL))\r\n],
        "OK Success\r\n"
      ])
      |> TestServer.tagged("FETCH 1 (BODY.PEEK[])\r\n", [
        "* 1 FETCH (BODY[] {17}\r\nSubject: Test\r\n\r\n)\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("STORE 1 +FLAGS (\\Deleted)\r\n", [
        "* 1 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("EXPUNGE\r\n", [
        "* 1 EXPUNGE\r\n",
        "OK Expunge completed\r\n"
      ])
      |> TestServer.tagged("IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.tagged("DONE\r\n", [
        "OK IDLE terminated\r\n"
      ])
      |> TestServer.tagged("LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "OK Logged out\r\n"
      ])
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, pid} =
          TestMailRouter.start_link(
            server: server.address,
            port: server.port,
            ssl: true,
            assigns: %{test_pid: self()},
            debug: @debug
          )

        assert_receive({:match_and_fetch, 1, <<"Subject: ", _rest::binary>>, %Mail.Message{}})
        TestMailRouter.close(pid)
      end)

    assert log =~ "Processing 1 emails"

    assert log =~
             "Processing msg:1 TO:george@example.com FROM:andrew@internuity.net SUBJECT:\"To be fetched\" using Mailroom.InboxTest.TestMailProcessor#match_and_fetch -> :delete"
  end

  test "Match by header" do
    server = TestServer.start(ssl: true)

    headers =
      Mail.build_multipart()
      |> Mail.put_from("andrew@internuity.net")
      |> Mail.put_subject("Test with header")
      |> Mail.put_to("reply@example.com")
      |> Mail.Message.put_header("in-reply-to", "message-id")
      |> Mail.Renderers.RFC2822.render()
      |> String.split("\r\n\r\n")
      |> List.first()

    TestServer.expect(server, fn expectations ->
      expectations
      |> TestServer.tagged(:connect, "* OK IMAP ready\r\n")
      |> TestServer.tagged("LOGIN \"test@example.com\" \"P@55w0rD\"\r\n", [
        "* CAPABILITY (IMAPrev4)\r\n",
        "OK test@example.com authenticated (Success)\r\n"
      ])
      |> TestServer.tagged("SELECT INBOX\r\n", [
        "* FLAGS (\\Flagged \\Draft \\Deleted \\Seen)\r\n",
        "* OK [PERMANENTFLAGS (\\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted\r\n",
        "* 1 EXISTS\r\n",
        "* 0 RECENT\r\n",
        "OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.tagged("SEARCH UNSEEN\r\n", [
        "* SEARCH 1\r\n",
        "OK Success\r\n"
      ])
      |> TestServer.tagged("FETCH 1 (ENVELOPE BODY.PEEK[HEADER])\r\n", [
        ~s[* 1 FETCH (ENVELOPE ("Mon, 27 Jul 2020 11:57:36 +0200" "Test with header" (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) ((NIL NIL "reply" "example.com")) NIL NIL "<f69b912d-310b-4133-b526-07f715242db6@Spark>" "<4cff0831-67f5-4457-b60a-3331ba893348@Spark>") BODY\[HEADER\] {#{byte_size(headers)}}\r\n#{headers})\r\n],
        "OK Success\r\n"
      ])
      |> TestServer.tagged("STORE 1 +FLAGS (\\Deleted)\r\n", [
        "* 1 FETCH (FLAGS (\\Deleted))\r\n",
        "OK Store completed\r\n"
      ])
      |> TestServer.tagged("EXPUNGE\r\n", [
        "* 1 EXPUNGE\r\n",
        "OK Expunge completed\r\n"
      ])
      |> TestServer.tagged("IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.tagged("DONE\r\n", [
        "OK IDLE terminated\r\n"
      ])
      |> TestServer.tagged("LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "OK Logged out\r\n"
      ])
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, pid} =
          TestMailHeaderRouter.start_link(
            server: server.address,
            port: server.port,
            ssl: true,
            assigns: %{test_pid: self()},
            debug: @debug
          )

        assert_receive({:match_header, 1})
        TestMailHeaderRouter.close(pid)
      end)

    assert log =~ "Processing 1 emails"

    assert log =~
             "Processing msg:1 TO:reply@example.com FROM:andrew@internuity.net SUBJECT:\"Test with header\" using Mailroom.InboxTest.TestMailProcessor#match_header -> :delete"
  end
end
