defmodule IndoorsExperimentsWeb.HuntChannelTest do
  use IndoorsExperimentsWeb.ChannelCase, async: true

  import IndoorsExperiments.VisionFixtures

  alias IndoorsExperimentsWeb.{HuntChannel, UserSocket}

  setup do
    {:ok, reply, socket} =
      UserSocket
      |> socket()
      |> subscribe_and_join(HuntChannel, "hunt:test", %{"target" => "bus"})

    %{socket: socket, join_reply: reply}
  end

  test "joining lists the possible targets", %{join_reply: reply} do
    assert %{targets: [%{class: _, emoji: _, points: _} | _], model_ready: true} = reply
  end

  test "frames come back with the game state", %{socket: socket} do
    ref = push(socket, "frame", {:binary, frame_message(1, 0)})
    assert_reply ref, :ok, %{hunt: %{target: %{class: "bus"}, phase: :hunting}}, 5_000
  end

  test "skip picks a new target", %{socket: socket} do
    ref = push(socket, "frame", {:binary, frame_message(1, 0)})
    assert_reply ref, :ok, _, 5_000

    ref = push(socket, "skip", %{"t" => 500})
    assert_reply ref, :ok, %{hunt: %{skipped: 1, target: %{class: class}}}, 2_000
    refute class == "bus"
  end

  defp frame_message(seq, t) do
    header = Jason.encode!(%{seq: seq, t: t})
    <<byte_size(header)::32, header::binary, jpeg("bus.jpg")::binary>>
  end
end
