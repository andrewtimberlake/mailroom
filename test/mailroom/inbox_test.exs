defmodule Mailroom.InboxTest do
  use ExUnit.Case, async: true

  alias Mailroom.TestServer

  @debug false

  defmodule TestMailProcessor do
    def match_subject_regex(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_subject_regex, msg_id})
    end

    def match_subject_string(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_subject_string, msg_id})
    end

    def match_has_attachment(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_has_attachment, msg_id})
    end
  end

  defmodule TestMailRouterEnvelopeOnly do
    use Mailroom.Inbox

    def config(opts) do
      Keyword.merge(opts, username: "test@example.com", password: "P@55w0rD")
    end

    match(
      [
        to: %{mailbox_name: "john", host_name: "example.com"},
        to: %{mailbox_name: "jane", host_name: "example.com"}
      ],
      :match_to
    )

    match([subject: ~r/test \d+/i], TestMailProcessor, :match_subject_regex)
    match([subject: "Testing 3"], TestMailProcessor, :match_subject_string)

    def match_to(%{id: msg_id, assigns: %{test_pid: pid}}) do
      send(pid, {:matched_to, msg_id})
    end
  end

  defmodule TestMailRouter do
    use Mailroom.Inbox

    def config(opts) do
      Keyword.merge(opts, username: "test@example.com", password: "P@55w0rD")
    end

    match([has_attachment: true], TestMailProcessor, :match_has_attachment)
  end

  test "Can match on any TO" do
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
        "* 0 EXISTS\r\n",
        "* 0 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 IDLE\r\n", [
        "+ idling\r\n",
        "* 3 EXISTS\r\n"
      ])
      |> TestServer.on("DONE\r\n", [
        "A003 OK IDLE terminated\r\n"
      ])
      |> TestServer.on("A004 FETCH 1:3 (ENVELOPE)\r\n", [
        "* 1 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:23:14 +0200\" \"The subject\" ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"John Doe\" NIL \"john\" \"example.com\")) NIL NIL NIL \"<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>\"))\r\n",
        "* 2 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:23:14 +0200\" \"The subject\" ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Jane Doe\" NIL \"JANE\" \"EXAMPLE.COM\")) NIL NIL NIL \"<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>\"))\r\n",
        "* 3 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:24:15 +0200\" \"The subject\" ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((NIL NIL \"george\" \"example.com\")) NIL NIL \"652E7B61-60F6-421C-B954-4178BB769B27.example.com\" \"<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>\"))\r\n",
        "A004 OK Success\r\n"
      ])
      |> TestServer.on("A005 IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.on("DONE\r\n", [
        "A005 OK IDLE terminated\r\n"
      ])
      |> TestServer.on("A006 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A006 OK Logged out\r\n"
      ])
    end)

    ExUnit.CaptureLog.capture_log(fn ->
      {:ok, pid} =
        TestMailRouterEnvelopeOnly.start_link(
          server: server.address,
          port: server.port,
          ssl: true,
          assigns: %{test_pid: self()},
          debug: @debug
        )

      assert_receive({:matched_to, 1})
      assert_receive({:matched_to, 2})
      refute_receive({:matched_to, _})
      TestMailRouterEnvelopeOnly.close(pid)
    end)
  end

  test "Can match on a subject" do
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
        "* 0 EXISTS\r\n",
        "* 0 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 IDLE\r\n", [
        "+ idling\r\n",
        "* 3 EXISTS\r\n"
      ])
      |> TestServer.on("DONE\r\n", [
        "A003 OK IDLE terminated\r\n"
      ])
      |> TestServer.on("A004 FETCH 1:3 (ENVELOPE)\r\n", [
        "* 1 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:23:14 +0200\" \"First one\" ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"Bob Jones\" NIL \"bob\" \"example.com\")) ((\"John Doe\" NIL \"bruce\" \"example.com\")) NIL NIL NIL \"<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>\"))\r\n",
        "* 2 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:24:15 +0200\" \"Test 2\" ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((NIL NIL \"george\" \"example.com\")) NIL NIL \"652E7B61-60F6-421C-B954-4178BB769B27.example.com\" \"<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>\"))\r\n",
        "* 3 FETCH (ENVELOPE (\"Wed, 26 Oct 2016 14:24:15 +0200\" \"Testing 3\" ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((\"Jane Doe\" NIL \"jane\" \"example.com\")) ((NIL NIL \"george\" \"example.com\")) NIL NIL \"652E7B61-60F6-421C-B954-4178BB769B27.example.com\" \"<28D03E0E-47EE-4AEF-BDE6-54ADB0EF28FD.example.com>\"))\r\n",
        "A004 OK Success\r\n"
      ])
      |> TestServer.on("A005 IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.on("DONE\r\n", [
        "A005 OK IDLE terminated\r\n"
      ])
      |> TestServer.on("A006 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A006 OK Logged out\r\n"
      ])
    end)

    ExUnit.CaptureLog.capture_log(fn ->
      {:ok, pid} =
        TestMailRouterEnvelopeOnly.start_link(
          server: server.address,
          port: server.port,
          ssl: true,
          assigns: %{test_pid: self()},
          debug: @debug
        )

      assert_receive({:matched_subject_regex, 2})
      assert_receive({:matched_subject_string, 3})
      refute_receive({:matched_to, _})
      TestMailRouterEnvelopeOnly.close(pid)
    end)
  end

  test "Can match on an having an attachment" do
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
        "* 0 RECENT\r\n",
        "A002 OK [READ-WRITE] INBOX selected. (Success)\r\n"
      ])
      |> TestServer.on("A003 FETCH 1:2 (BODYSTRUCTURE ENVELOPE)\r\n", [
        ~s[* 1 FETCH (ENVELOPE ("Mon, 10 Jun 2019 11:57:36 +0200" "Attached." (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) ((NIL NIL "george" "example.com")) NIL NIL "<f69b912d-310b-4133-b526-07f715242db6@Spark>" "<4cff0831-67f5-4457-b60a-3331ba893348@Spark>") BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 8 1 NIL ("INLINE" NIL) NIL)(("TEXT" "HTML" ("CHARSET" "utf-8") NIL NIL "QUOTED-PRINTABLE" 293 6 NIL ("INLINE" NIL) NIL)("IMAGE" "PNG" NIL "<D0C5BB9CBFAE48E09727D1A67721F939>" NIL "BASE64" 3934 NIL ("INLINE" ("FILENAME" "3M-Logo.png")) NIL) "RELATED" ("BOUNDARY" "5cfe29a0_507ed7ab_d312") NIL NIL) "ALTERNATIVE" ("BOUNDARY" "5cfe29a0_2eb141f2_d312") NIL NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 2730568 NIL ("ATTACHMENT" ("FILENAME" "test.pdf")) NIL) "MIXED" ("BOUNDARY" "5cfe29a0_41b71efb_d312") NIL NIL))\r\n],
        ~s[* 2 FETCH (ENVELOPE ("Tue, 11 Jun 2019 09:21:23 +0200" "Test with multiple attachments" (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) (("Andrew Timberlake" NIL "andrew" "internuity.net")) ((NIL NIL "george" "example.com")) NIL NIL "<60f5c212-a3a0-464d-b287-6d81f46a1359@Spark>" "<ada126ec-8244-4abd-b3bf-a793d456fd4e@Spark>") BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "7BIT" 9 1 NIL ("INLINE" NIL) NIL)("TEXT" "HTML" ("CHARSET" "utf-8") NIL NIL "QUOTED-PRINTABLE" 195 4 NIL ("INLINE" NIL) NIL) "ALTERNATIVE" ("BOUNDARY" "5cff5678_ded7263_d312") NIL NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 2 NIL ("ATTACHMENT" ("FILENAME" "test.csv")) NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 14348938 NIL ("ATTACHMENT" ("FILENAME" "test.doc")) NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 240 NIL ("ATTACHMENT" ("FILENAME" "test.mid")) NIL)("TEXT" "PLAIN" NIL NIL NIL "BASE64" 10 1 NIL ("ATTACHMENT" ("FILENAME" "test.txt")) NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" 974 NIL ("ATTACHMENT" ("FILENAME" "test.wav")) NIL) "MIXED" ("BOUNDARY" "5cff5678_7fdcc233_d312") NIL NIL))\r\n],
        "A003 OK Success\r\n"
      ])
      |> TestServer.on("A004 IDLE\r\n", [
        "+ idling\r\n"
      ])
      |> TestServer.on("DONE\r\n", [
        "A004 OK IDLE terminated\r\n"
      ])
      |> TestServer.on("A005 LOGOUT\r\n", [
        "* BYE We're out of here\r\n",
        "A005 OK Logged out\r\n"
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

      assert_receive({:matched_has_attachment, 1})
      assert_receive({:matched_has_attachment, 2})
      TestMailRouter.close(pid)
    end)
  end
end
