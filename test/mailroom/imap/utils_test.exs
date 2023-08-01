defmodule Mailroom.IMAP.UtilsTest do
  use ExUnit.Case, async: true

  import Mailroom.IMAP.Utils

  describe "parse_list/1" do
    test "with simple list" do
      assert parse_list("(one two three)") == {["one", "two", "three"], ""}
    end

    test "with empty list" do
      assert parse_list("()") == {[], ""}
    end

    test "with nested list" do
      assert parse_list("(one (two three) four)") == {["one", ["two", "three"], "four"], ""}
    end

    test "with nested lists" do
      assert parse_list("(one (two (three)) four)") == {["one", ["two", ["three"]], "four"], ""}
    end

    test "with nested empty list" do
      assert parse_list("(one () four)") == {["one", [], "four"], ""}
    end

    test "with doubly nested list" do
      assert parse_list("(one ((two three)) four)") == {["one", [["two", "three"]], "four"], ""}
    end

    test "with strings" do
      assert parse_list("(one \"two three\" four)") == {["one", "two three", "four"], ""}
    end

    test "with literal string" do
      assert parse_list("(BODY[TEXT] {8}\r\nTest 1\r\n)\r\n") ==
               {["BODY[TEXT]", "Test 1\r\n"], "\r\n"}
    end

    test "with NIL" do
      assert parse_list("(one NIL four)") == {["one", nil, "four"], ""}
      assert parse_list("(NIL)") == {[nil], ""}
    end

    test "with extraneous data" do
      assert parse_list("(one two) three") == {["one", "two"], " three"}
      assert parse_list("(one two)\r\n") == {["one", "two"], "\r\n"}
    end
  end

  test "parse_list_only/1" do
    assert parse_list_only("(one two)") == ["one", "two"]
    assert parse_list_only("(one (two three))") == ["one", ["two", "three"]]
    assert parse_list_only("(one ((two three)))") == ["one", [["two", "three"]]]
    assert parse_list_only("(one (\"two\" (three)))\r\n") == ["one", ["two", ["three"]]]
    assert parse_list_only("(one (two) (three))") == ["one", ["two"], ["three"]]
  end

  test "parse_string/1" do
    assert parse_string("one two") == {"one", " two"}
    assert parse_string("one\r\n") == {"one", "\r\n"}
    assert parse_string("\"one\" two") == {"one", " two"}
    assert parse_string("\"one two\"") == {"one two", ""}
    assert parse_string("\"one\\\"two\"") == {"one\"two", ""}
  end

  test "parse_string_only/1" do
    assert parse_string_only("one\r\n") == "one"
    assert parse_string_only("\"one\" two") == "one"
    assert parse_string_only("\"one two\"") == "one two"
    assert parse_string_only("\"one\\\"two\"") == "one\"two"
  end

  test "items_to_list/1" do
    assert items_to_list("MESSAGES") == ["(", "MESSAGES", ")"]
    assert items_to_list(["MESSAGES", "RECENT"]) == ["(", "MESSAGES", " ", "RECENT", ")"]
    assert items_to_list([:messages, :recent]) == ["(", "MESSAGES", " ", "RECENT", ")"]
  end

  test "list_to_status_items/1" do
    assert list_to_status_items(["MESSAGES", "4", "RECENT", "2", "UNSEEN", "1"]) == %{
             messages: 4,
             recent: 2,
             unseen: 1
           }
  end

  test "list_to_items/1" do
    map =
      list_to_items([
        "RFC822.SIZE",
        "3325",
        "INTERNALDATE",
        "26-Oct-2016 12:23:20 +0000",
        "FLAGS",
        ["Seen"]
      ])

    assert map == %{
             rfc822_size: "3325",
             internal_date: "26-Oct-2016 12:23:20 +0000",
             flags: ["Seen"]
           }
  end

  test "flags_to_list/1" do
    assert flags_to_list(["\\Seen", "\\Answered"]) == ["(", "\\Seen", " ", "\\Answered", ")"]

    assert flags_to_list([:seen, :answered, :flagged, :deleted, :draft, :recent]) == [
             "(",
             "\\Seen",
             " ",
             "\\Answered",
             " ",
             "\\Flagged",
             " ",
             "\\Deleted",
             " ",
             "\\Draft",
             " ",
             "\\Recent",
             ")"
           ]
  end

  test "list_to_flags/1" do
    assert list_to_flags([
             "\\Seen",
             "\\Answered",
             "\\Flagged",
             "\\Deleted",
             "\\Draft",
             "\\Recent",
             "Other"
           ]) == [:seen, :answered, :flagged, :deleted, :draft, :recent, "Other"]
  end

  describe "parse_number/1" do
    test "with a single digit" do
      assert parse_number("1") == 1
      assert parse_number("0") == 0
    end

    test "with multiple digits" do
      assert parse_number("12345") == 12345
      assert parse_number("352841") == 352_841
    end

    test "with digits followed by other data" do
      assert parse_number("12345Bob") == 12345
      assert parse_number("352841 more data") == 352_841
    end
  end

  test "quote_string/1" do
    assert quote_string("string") == "\"string\""
    assert quote_string("str ing") == "\"str ing\""
    assert quote_string("str\"ing") == "\"str\\\"ing\""
  end

  test "numbers_to_sequences/1" do
    assert numbers_to_sequences([]) == []
    assert numbers_to_sequences([1, 2, 4]) == [1..2, 4]
    assert numbers_to_sequences([1, 4, 2]) == [1..2, 4]

    assert numbers_to_sequences([1, 2, 3, 4, 7, 9, 11, 22, 23, 24, 25, 26, 30]) == [
             1..4,
             7,
             9,
             11,
             22..26,
             30
           ]

    assert numbers_to_sequences([1, 2, 3, 4, 7, 9, 11, 22, 23, 24, 25, 26, 30, 45, 46]) == [
             1..4,
             7,
             9,
             11,
             22..26,
             30,
             45..46
           ]

    assert numbers_to_sequences([1, 3, 5, 7, 9, 2, 4, 6, 8, 10]) == [1..10]
    assert numbers_to_sequences([1, 3, 5, 7, 9, 2, 4, 6, 8, 10, 1, 3, 5, 7, 9]) == [1..10]
  end

  test "parse_timestamp/1" do
    assert parse_timestamp("21-Jun-2018 17:51:47 +0000") == ~U"2018-06-21 17:51:47Z"
  end
end
