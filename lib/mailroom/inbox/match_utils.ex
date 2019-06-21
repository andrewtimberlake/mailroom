defmodule Mailroom.Inbox.MatchUtils do
  alias Mailroom.IMAP.{Envelope, BodyStructure}
  alias BodyStructure.Part

  def match_recipient(%{to: to, cc: cc, bcc: bcc}, pattern) do
    Enum.any?([to, cc, bcc], fn list ->
      match_in_list(list, pattern)
    end)
  end

  def match_to(%{to: to}, pattern) do
    match_in_list(to, pattern)
  end

  def match_cc(%{cc: cc}, pattern) do
    match_in_list(cc, pattern)
  end

  def match_bcc(%{bcc: bcc}, pattern) do
    match_in_list(bcc, pattern)
  end

  def match_from(%{from: from}, pattern) do
    match_in_list(from, pattern)
  end

  def match_subject(%{subject: pattern}, pattern), do: true
  def match_subject(%{subject: subject}, %Regex{} = pattern), do: Regex.match?(pattern, subject)
  def match_subject(%{subject: _subject}, _pattern), do: false

  def match_has_attachment?(%{has_attachment: true}), do: true
  def match_has_attachment?(%{has_attachment: false}), do: false

  def match_all(_), do: true

  defp match_in_list(nil, _pattern), do: false
  defp match_in_list(string, pattern) when is_binary(string), do: match_in_list([string], pattern)
  defp match_in_list([], _pattern), do: false

  defp match_in_list([string | tail], %Regex{} = pattern) do
    if Regex.match?(pattern, string) do
      true
    else
      match_in_list(tail, pattern)
    end
  end

  defp match_in_list([pattern | _], pattern), do: true
  defp match_in_list([_head | tail], pattern), do: match_in_list(tail, pattern)

  def generate_mail_info(%Envelope{} = envelope, %Part{} = part) do
    %Envelope{to: to, cc: cc, bcc: bcc, from: from, reply_to: reply_to, subject: subject} =
      envelope

    has_attachment = BodyStructure.has_attachment?(part)

    %{
      to: Enum.map(List.wrap(to), &String.downcase(&1.email)),
      cc: Enum.map(List.wrap(cc), &String.downcase(&1.email)),
      bcc: Enum.map(List.wrap(bcc), &String.downcase(&1.email)),
      from: Enum.map(List.wrap(from), &String.downcase(&1.email)),
      reply_to: Enum.map(List.wrap(reply_to), &String.downcase(&1.email)),
      subject: subject,
      has_attachment: has_attachment
    }
  end
end
