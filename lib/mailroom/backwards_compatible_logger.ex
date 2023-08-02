# From https://jeffkreeftmeijer.com/elixir-backwards-compatible-logger/
defmodule Mailroom.BackwardsCompatibleLogger do
  require Logger

  defdelegate debug(message), to: Logger
  defdelegate info(message), to: Logger
  defdelegate error(message), to: Logger

  case Version.compare(System.version(), "1.11.0") do
    :lt -> defdelegate warning(message), to: Logger, as: :warn
    _ -> defdelegate warning(message), to: Logger
  end
end
