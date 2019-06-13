defmodule Mailroom.IMAP.BodyStructureTests do
  use ExUnit.Case, async: true

  alias Mailroom.IMAP.BodyStructure
  alias Mailroom.IMAP.BodyStructure.Part

  test "has_attachment?/1" do
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

    assert BodyStructure.has_attachment?(body_structure)

    body_structure = %Part{
      description: nil,
      disposition: nil,
      encoded_size: 1315,
      encoding: "quoted-printable",
      file_name: nil,
      id: nil,
      multipart: false,
      params: %{"charset" => "iso-8859-1"},
      parts: [],
      section: nil,
      type: "text/plain"
    }

    refute BodyStructure.has_attachment?(body_structure)

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
          encoded_size: 2234,
          encoding: "quoted-printable",
          file_name: nil,
          id: nil,
          multipart: false,
          params: %{"charset" => "iso-8859-1"},
          parts: [],
          section: "1",
          type: "text/plain"
        },
        %Part{
          description: nil,
          disposition: nil,
          encoded_size: 2987,
          encoding: "quoted-printable",
          file_name: nil,
          id: nil,
          multipart: false,
          params: %{"charset" => "iso-8859-1"},
          parts: [],
          section: "2",
          type: "text/html"
        }
      ],
      section: nil,
      type: "alternative"
    }

    refute BodyStructure.has_attachment?(body_structure)

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
          encoded_size: 119,
          encoding: "7bit",
          file_name: nil,
          id: nil,
          multipart: false,
          params: %{"charset" => "US-ASCII"},
          parts: [],
          section: "1",
          type: "text/html"
        },
        %Part{
          description: nil,
          disposition: "inline",
          encoded_size: 143_804,
          encoding: "base64",
          file_name: "4356415.jpg",
          id: "<0__=rhksjt>",
          multipart: false,
          params: %{"name" => "4356415.jpg"},
          parts: [],
          section: "2",
          type: "image/jpeg"
        }
      ],
      section: nil,
      type: "related"
    }

    refute BodyStructure.has_attachment?(body_structure)

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
          encoded_size: 2815,
          encoding: "quoted-printable",
          file_name: nil,
          id: nil,
          multipart: false,
          params: %{"charset" => "ISO-8859-1", "format" => "flowed"},
          parts: [],
          section: "1",
          type: "text/plain"
        },
        %Part{
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
              encoded_size: 4171,
              encoding: "quoted-printable",
              file_name: nil,
              id: nil,
              multipart: false,
              params: %{"charset" => "ISO-8859-1"},
              parts: [],
              section: "2.1",
              type: "text/html"
            },
            %Part{
              description: nil,
              disposition: nil,
              encoded_size: 189_906,
              encoding: "base64",
              file_name: nil,
              id: "<3245dsf7435>",
              multipart: false,
              params: %{"name" => "image.jpg"},
              parts: [],
              section: "2.2",
              type: "image/jpeg"
            },
            %Part{
              description: nil,
              disposition: nil,
              encoded_size: 1090,
              encoding: "base64",
              file_name: nil,
              id: "<32f6324f>",
              multipart: false,
              params: %{"name" => "other.gif"},
              parts: [],
              section: "2.3",
              type: "image/gif"
            }
          ],
          section: "2",
          type: "related"
        }
      ],
      section: nil,
      type: "alternative"
    }

    refute BodyStructure.has_attachment?(body_structure)

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
          encoded_size: 4692,
          encoding: "quoted-printable",
          file_name: nil,
          id: nil,
          multipart: false,
          params: %{"charset" => "ISO-8859-1"},
          parts: [],
          section: "1",
          type: "text/html"
        },
        %Part{
          description: nil,
          disposition: "attachment",
          encoded_size: 38838,
          encoding: "base64",
          file_name: "pages.pdf",
          id: nil,
          multipart: false,
          params: %{"name" => "pages.pdf"},
          parts: [],
          section: "2",
          type: "application/pdf"
        }
      ],
      section: nil,
      type: "mixed"
    }

    assert BodyStructure.has_attachment?(body_structure)

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
              encoded_size: 403,
              encoding: "quoted-printable",
              file_name: nil,
              id: nil,
              multipart: false,
              params: %{"charset" => "UTF-8"},
              parts: [],
              section: "1.1",
              type: "text/plain"
            },
            %Part{
              description: nil,
              disposition: nil,
              encoded_size: 421,
              encoding: "quoted-printable",
              file_name: nil,
              id: nil,
              multipart: false,
              params: %{"charset" => "UTF-8"},
              parts: [],
              section: "1.2",
              type: "text/html"
            }
          ],
          section: "1",
          type: "alternative"
        },
        %Part{
          description: nil,
          disposition: "attachment",
          encoded_size: 110_000,
          encoding: "base64",
          file_name: "letter.doc",
          id: nil,
          multipart: false,
          params: %{"name" => "letter.doc"},
          parts: [],
          section: "2",
          type: "application/msword"
        }
      ],
      section: nil,
      type: "mixed"
    }

    assert BodyStructure.has_attachment?(body_structure)
  end

  test "get_attachments/1" do
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

    assert [
             %Part{
               disposition: "attachment",
               file_name: "Image.pdf",
               section: "2",
               type: "application/octet-stream"
             }
           ] = BodyStructure.get_attachments(body_structure)

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
          encoded_size: 119,
          encoding: "7bit",
          file_name: nil,
          id: nil,
          multipart: false,
          params: %{"charset" => "US-ASCII"},
          parts: [],
          section: "1",
          type: "text/html"
        },
        %Part{
          description: nil,
          disposition: "inline",
          encoded_size: 143_804,
          encoding: "base64",
          file_name: "4356415.jpg",
          id: "<0__=rhksjt>",
          multipart: false,
          params: %{"name" => "4356415.jpg"},
          parts: [],
          section: "2",
          type: "image/jpeg"
        }
      ],
      section: nil,
      type: "related"
    }

    assert [] = BodyStructure.get_attachments(body_structure)

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
              encoded_size: 9,
              encoding: "7bit",
              file_name: nil,
              id: nil,
              multipart: false,
              params: %{"charset" => "utf-8"},
              parts: [],
              section: "1.1",
              type: "text/plain"
            },
            %Part{
              description: nil,
              disposition: nil,
              encoded_size: 195,
              encoding: "quoted-printable",
              file_name: nil,
              id: nil,
              multipart: false,
              params: %{"charset" => "utf-8"},
              parts: [],
              section: "1.2",
              type: "text/html"
            }
          ],
          section: "1",
          type: "alternative"
        },
        %Part{
          description: nil,
          disposition: "attachment",
          encoded_size: 2,
          encoding: "base64",
          file_name: "test.csv",
          id: nil,
          multipart: false,
          params: %{},
          parts: [],
          section: "2",
          type: "application/octet-stream"
        },
        %Part{
          description: nil,
          disposition: "attachment",
          encoded_size: 14_348_938,
          encoding: "base64",
          file_name: "test.doc",
          id: nil,
          multipart: false,
          params: %{},
          parts: [],
          section: "3",
          type: "application/octet-stream"
        },
        %Part{
          description: nil,
          disposition: "attachment",
          encoded_size: 240,
          encoding: "base64",
          file_name: "test.mid",
          id: nil,
          multipart: false,
          params: %{},
          parts: [],
          section: "4",
          type: "application/octet-stream"
        },
        %Part{
          description: nil,
          disposition: "attachment",
          encoded_size: 10,
          encoding: "base64",
          file_name: "test.txt",
          id: nil,
          multipart: false,
          params: %{},
          parts: [],
          section: "5",
          type: "text/plain"
        },
        %Part{
          description: nil,
          disposition: "attachment",
          encoded_size: 974,
          encoding: "base64",
          file_name: "test.wav",
          id: nil,
          multipart: false,
          params: %{},
          parts: [],
          section: "6",
          type: "application/octet-stream"
        }
      ],
      section: nil,
      type: "mixed"
    }

    assert [
             %Part{
               disposition: "attachment",
               file_name: "test.csv",
               section: "2",
               type: "application/octet-stream"
             },
             %Part{
               disposition: "attachment",
               file_name: "test.doc",
               section: "3",
               type: "application/octet-stream"
             },
             %Part{
               disposition: "attachment",
               file_name: "test.mid",
               section: "4",
               type: "application/octet-stream"
             },
             %Part{
               disposition: "attachment",
               file_name: "test.txt",
               section: "5",
               type: "text/plain"
             },
             %Part{
               disposition: "attachment",
               file_name: "test.wav",
               section: "6",
               type: "application/octet-stream"
             }
           ] = BodyStructure.get_attachments(body_structure)
  end
end
