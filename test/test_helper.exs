Code.compile_file("test_server.ex", __DIR__)
Mailroom.TestServer.Application.start(nil, nil)
ExUnit.start()
