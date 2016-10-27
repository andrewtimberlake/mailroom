defmodule Mailroom.IMAP.UtilsTest do
  use ExUnit.Case, async: true

  import Mailroom.IMAP.Utils

  describe "parse_list/1" do
    test "with simple list" do
      assert parse_list("(one two three)") == ["one", "two", "three"]
    end

    test "with [] brackets" do
      assert parse_list("[one two three]") == ["one", "two", "three"]
    end

    test "with empty list" do
      assert parse_list("()") == []
    end

    test "with nested list" do
      assert parse_list("(one (two three) four)") == ["one", ["two", "three"], "four"]
    end

    test "with nested lists" do
      assert parse_list("(one (two (three)) four)") == ["one", ["two", ["three"]], "four"]
    end

    test "with nested empty list" do
      assert parse_list("(one () four)") == ["one", [], "four"]
    end
  end

  describe "parse_number/1" do
    test "with a single digit" do
      assert parse_number("1") == 1
      assert parse_number("0") == 0
    end

    test "with multiple digits" do
      assert parse_number("12345") == 12345
      assert parse_number("352841") == 352841
    end

    test "with digits followed by other data" do
      assert parse_number("12345Bob") == 12345
      assert parse_number("352841 more data") == 352841
    end
  end
end
