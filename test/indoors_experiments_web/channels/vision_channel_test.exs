defmodule IndoorsExperimentsWeb.VisionChannelTest do
  use IndoorsExperimentsWeb.ChannelCase, async: true

  import IndoorsExperiments.VisionFixtures

  alias IndoorsExperimentsWeb.{UserSocket, VisionChannel}

  setup do
    {:ok, join_reply, socket} =
      UserSocket
      |> socket()
      |> subscribe_and_join(VisionChannel, "vision:test")

    %{socket: socket, join_reply: join_reply}
  end

  test "joining sends the lane outline", %{join_reply: reply} do
    assert %{lane: %{polygon: [_, _, _, _]}, model_ready: true} = reply
  end

  test "a binary frame comes back with tracks and a decision", %{socket: socket} do
    header = Jason.encode!(%{seq: 7, t: 1_000, orientation: nil})
    message = <<byte_size(header)::32, header::binary, jpeg("bus.jpg")::binary>>

    ref = push(socket, "frame", {:binary, message})
    assert_reply ref, :ok, %{seq: 7, tracks: tracks, decision: %{level: _}}, 5_000

    assert Enum.any?(tracks, &(&1.class == "bus"))
  end

  test "garbage is rejected", %{socket: socket} do
    ref = push(socket, "frame", {:binary, <<0, 0>>})
    assert_reply ref, :error, %{reason: "malformed frame"}
  end
end
