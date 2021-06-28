defmodule Mailroom.Inbox.MatchUtilsTest do
  use ExUnit.Case, async: true
  import Mailroom.Inbox.MatchUtils

  alias Mailroom.IMAP.{BodyStructure, Envelope}
  alias BodyStructure.Part

  test "match_recipient/2 with binary" do
    mail_info = %{
      recipients: [
        "test-to@example.com",
        "other-to@example.com",
        "test-cc@example.com",
        "other-cc@example.com",
        "test-bcc@example.com"
      ],
      to: ["test-to@example.com", "other-to@example.com"],
      cc: ["test-cc@example.com", "other-cc@example.com"],
      bcc: "test-bcc@example.com"
    }

    assert match_recipient(mail_info, "test-to@example.com")
    assert match_recipient(mail_info, "other-to@example.com")

    assert match_recipient(mail_info, "test-cc@example.com")
    assert match_recipient(mail_info, "other-cc@example.com")

    assert match_recipient(mail_info, "test-bcc@example.com")

    refute match_recipient(mail_info, "no-to@example.com")
    refute match_recipient(mail_info, "no-cc@example.com")
    refute match_recipient(mail_info, "no-bcc@example.com")
  end

  test "match_recipient/2 with Regex" do
    mail_info = %{
      recipients: [
        "test-to@example.com",
        "other-to@example.com",
        "test-cc@example.com",
        "other-cc@example.com",
        "test-bcc@example.com"
      ],
      to: ["test-to@example.com", "other-to@example.com"],
      cc: ["test-cc@example.com", "other-cc@example.com"],
      bcc: "test-bcc@example.com"
    }

    assert match_recipient(mail_info, ~r/to@example/)
    assert match_recipient(mail_info, ~r/bcc/)
    refute match_recipient(mail_info, ~r/\d+/)
  end

  test "match_to/2 with binary" do
    mail_info = %{
      to: ["test-to@example.com", "other-to@example.com"],
      cc: ["test-cc@example.com", "other-cc@example.com"],
      bcc: "test-bcc@example.com"
    }

    assert match_to(mail_info, "test-to@example.com")
    assert match_to(mail_info, "other-to@example.com")

    refute match_to(mail_info, "test-cc@example.com")
    refute match_to(mail_info, "other-cc@example.com")

    refute match_to(mail_info, "test-bcc@example.com")

    refute match_to(mail_info, "no-to@example.com")
    refute match_to(mail_info, "no-cc@example.com")
    refute match_to(mail_info, "no-bcc@example.com")
  end

  test "match_cc/2 with binary" do
    mail_info = %{
      to: ["test-to@example.com", "other-to@example.com"],
      cc: ["test-cc@example.com", "other-cc@example.com"],
      bcc: "test-bcc@example.com"
    }

    refute match_cc(mail_info, "test-to@example.com")
    refute match_cc(mail_info, "other-to@example.com")

    assert match_cc(mail_info, "test-cc@example.com")
    assert match_cc(mail_info, "other-cc@example.com")

    refute match_cc(mail_info, "test-bcc@example.com")

    refute match_cc(mail_info, "no-to@example.com")
    refute match_cc(mail_info, "no-cc@example.com")
    refute match_cc(mail_info, "no-bcc@example.com")
  end

  test "match_bcc/2 with binary" do
    mail_info = %{
      to: ["test-to@example.com", "other-to@example.com"],
      cc: ["test-cc@example.com", "other-cc@example.com"],
      bcc: "test-bcc@example.com"
    }

    refute match_bcc(mail_info, "test-to@example.com")
    refute match_bcc(mail_info, "other-to@example.com")

    refute match_bcc(mail_info, "test-cc@example.com")
    refute match_bcc(mail_info, "other-cc@example.com")

    assert match_bcc(mail_info, "test-bcc@example.com")

    refute match_bcc(mail_info, "no-to@example.com")
    refute match_bcc(mail_info, "no-cc@example.com")
    refute match_bcc(mail_info, "no-bcc@example.com")
  end

  test "match_from/2 with binary" do
    mail_info = %{
      from: ["test-from@example.com", "other-from@example.com"]
    }

    assert match_from(mail_info, "test-from@example.com")
    assert match_from(mail_info, "other-from@example.com")
    refute match_from(mail_info, "no-from@example.com")
  end

  test "match_subject/2 with binary" do
    mail_info = %{
      subject: "Test subject"
    }

    assert match_subject(mail_info, "Test subject")
    refute match_subject(mail_info, "Test subject with more")
  end

  test "match_subject/2 with Regex" do
    mail_info = %{
      subject: "Test subject"
    }

    assert match_subject(mail_info, ~r/test/i)
    refute match_subject(mail_info, ~r/\d+/)
  end

  test "match_has_attachment?/1" do
    assert match_has_attachment?(%{has_attachment: true})
    refute match_has_attachment?(%{has_attachment: false})
  end

  test "generate_match_info/1" do
    envelope =
      Envelope.new([
        "Wed, 26 Oct 2016 14:23:14 +0200",
        "Test subject",
        [["John Doe", nil, "john", "example.com"]],
        [["John Doe", nil, "JOHN", "EXAMPLE.COM"]],
        [["John Doe", nil, "reply", "example.com"]],
        [[nil, nil, "dev", "debtflow.co.za"]],
        nil,
        nil,
        nil,
        "<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>"
      ])

    body_structure = %Part{
      description: nil,
      disposition: nil,
      encoded_size: nil,
      encoding: nil,
      file_name: nil,
      id: nil,
      multipart: true,
      params: %{},
      parts: [
        %Part{
          description: nil,
          disposition: nil,
          encoded_size: 438,
          encoding: "7bit",
          file_name: nil,
          id: nil,
          multipart: false,
          params: %{"charset" => "utf-8"},
          parts: [],
          section: "1",
          type: "text/plain"
        },
        %Part{
          description: nil,
          disposition: "attachment",
          encoded_size: 81800,
          encoding: "base64",
          file_name: "Image.pdf",
          id: nil,
          multipart: false,
          params: %{"name" => "Image.pdf"},
          parts: [],
          section: "2",
          type: "application/octet-stream"
        }
      ],
      section: nil,
      type: "mixed"
    }

    assert %{
             to: ["dev@debtflow.co.za"],
             cc: [],
             bcc: [],
             from: ["john@example.com"],
             reply_to: ["reply@example.com"],
             subject: "Test subject"
           } = generate_mail_info(%{envelope: envelope, body_structure: body_structure})
  end

  test "generate_match_info/1 with invalid data" do
    envelope =
      Envelope.new([
        "Wed, 26 Oct 2016 14:23:14 +0200",
        "Test subject",
        [["John Doe", nil, "john", "example.com"]],
        [["John Doe", nil, "JOHN", "EXAMPLE.COM"]],
        [["John Doe", nil, "reply", "example.com"]],
        [[nil, nil, "dev", "debtflow.co.za"]],
        nil,
        nil,
        nil,
        "<B042B704-E13E-44A2-8FEC-67A43B6DD6DB@example.com>"
      ])

    headers = "wrong"

    assert %{
             to: ["dev@debtflow.co.za"],
             cc: [],
             bcc: [],
             from: ["john@example.com"],
             reply_to: ["reply@example.com"],
             subject: "Test subject",
             headers: %{}
           } = generate_mail_info(%{:envelope => envelope, "BODY[HEADER]" => headers})
  end
end
