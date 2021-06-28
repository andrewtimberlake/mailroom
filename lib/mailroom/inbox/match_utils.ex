defmodule Mailroom.Inbox.MatchUtils do
  alias Mailroom.IMAP.{Envelope, BodyStructure}

  def match_recipient(%{recipients: recipients}, pattern) do
    match_in_list(recipients, pattern)
  end

  def match_to(%{to: to}, pattern) do
    match_in_list(to, pattern)
  end

  def match_to(_, _pattern), do: false

  def match_cc(%{cc: cc}, pattern) do
    match_in_list(cc, pattern)
  end

  def match_cc(_, _pattern), do: false

  def match_bcc(%{bcc: bcc}, pattern) do
    match_in_list(bcc, pattern)
  end

  def match_bcc(_, _pattern), do: false

  def match_from(%{from: from}, pattern) do
    match_in_list(from, pattern)
  end

  def match_from(_, _pattern), do: false

  def match_subject(%{subject: pattern}, pattern), do: true
  def match_subject(%{subject: subject}, %Regex{} = pattern), do: Regex.match?(pattern, subject)
  def match_subject(_, _pattern), do: false

  def match_has_attachment?(%{has_attachment: true}), do: true
  def match_has_attachment?(%{has_attachment: false}), do: false
  def match_has_attachment?(_), do: false

  def match_header(%{headers: headers}, header_name, %Regex{} = pattern) do
    headers[String.downcase(header_name)]
    |> List.wrap()
    |> Enum.any?(fn header_value -> Regex.match?(pattern, header_value) end)
  end

  def match_header(%{headers: headers}, header_name, pattern) do
    headers[String.downcase(header_name)]
    |> List.wrap()
    |> Enum.any?(&(&1 == pattern))
  end

  def match_header(_, _header_name, _pattern), do: false

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

  def generate_mail_info(%{envelope: %Envelope{} = envelope} = response) do
    %Envelope{to: to, cc: cc, bcc: bcc, from: from, reply_to: reply_to, subject: subject} =
      envelope

    to = get_email_addresses(to)
    cc = get_email_addresses(cc)
    bcc = get_email_addresses(bcc)

    recipients = Enum.flat_map([to, cc, bcc], & &1) |> Enum.uniq()

    has_attachment =
      case response do
        %{body_structure: part} ->
          BodyStructure.has_attachment?(part)

        _ ->
          false
      end

    headers =
      case response do
        %{"BODY[HEADER]" => headers} ->
          try do
            %{headers: headers} = Mail.Parsers.RFC2822.parse(headers <> "\r\n")
            headers
          rescue
            _ ->
              %{}
          end

        _ ->
          %{}
      end

    %{
      recipients: recipients,
      to: to,
      cc: cc,
      bcc: bcc,
      from: get_email_addresses(from),
      reply_to: get_email_addresses(reply_to),
      subject: subject || "",
      has_attachment: has_attachment,
      headers: headers
    }
  end

  def generate_mail_info(%{envelope: :error}) do
    :error
  end

  defp get_email_addresses(list) do
    Enum.map(List.wrap(list), &String.downcase(&1.email))
  end
end
