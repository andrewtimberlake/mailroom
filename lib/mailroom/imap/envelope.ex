defmodule Mailroom.IMAP.Envelope do
  defstruct ~w[date subject from sender reply_to to cc bcc in_reply_to message_id]a

  import Mailroom.IMAP.Utils

  @doc ~S"""
  Generates an `Envelope` struct from the IMAP ENVELOPE list
  """
  def new(list) do
    [date, subject, from, sender, reply_to, to, cc, bcc, in_reply_to, message_id] = list

    %__MODULE__{
      date: Mail.Parsers.RFC2822.erl_from_timestamp(date),
      subject: subject,
      from: parse_addresses(from),
      sender: parse_addresses(sender),
      reply_to: parse_addresses(reply_to),
      to: parse_addresses(to),
      cc: parse_addresses(cc),
      bcc: parse_addresses(bcc),
      in_reply_to: in_reply_to,
      message_id: message_id
    }
  end

  defp parse_addresses(nil), do: []
  defp parse_addresses([]), do: []

  defp parse_addresses(values) do
    Enum.map(values, fn [name, _smtp_source_route, mailbox_name, host_name] ->
      {name, mailbox_name, host_name}
    end)
  end
end
