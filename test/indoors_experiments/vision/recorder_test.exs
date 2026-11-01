defmodule IndoorsExperiments.Vision.RecorderTest do
  # Not async: it switches recording on for the whole app while it runs.
  use IndoorsExperimentsWeb.ChannelCase, async: false

  import IndoorsExperiments.VisionFixtures

  alias IndoorsExperiments.Vision.SessionReport
  alias IndoorsExperimentsWeb.{UserSocket, VisionChannel}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:indoors_experiments, :recordings_dir, tmp_dir)
    on_exit(fn -> Application.put_env(:indoors_experiments, :recordings_dir, nil) end)
  end

  test "a session leaves frames, snapshots and a readable report behind", %{tmp_dir: tmp_dir} do
    {:ok, %{recording: true}, socket} =
      UserSocket
      |> socket()
      |> subscribe_and_join(VisionChannel, "vision:recorder-test", %{"user_agent" => "test"})

    push(socket, "client_log", %{"level" => "warning", "message" => "camera is upside down"})

    for {jpeg, i} <- Enum.with_index(approaching_frames(12, 1.5)) do
      header = Jason.encode!(%{seq: i + 1, t: i * 125, client: %{round_trip_ms: 70}})

      ref =
        push(socket, "frame", {:binary, <<byte_size(header)::32, header::binary, jpeg::binary>>})

      assert_reply ref, :ok, _, 5_000
    end

    session = Path.join(tmp_dir, "latest")

    assert session
           |> Path.join("frames.jsonl")
           |> File.read!()
           |> String.split("\n", trim: true)
           |> length() == 12

    # Snapshots are written by a background task; give it a moment.
    Process.sleep(500)
    assert Path.wildcard(Path.join([session, "annotated", "*.jpg"])) != []

    {text, sheet} = SessionReport.build(session)
    assert text =~ "Frames: 12"
    assert text =~ "YIELD"
    assert text =~ "camera is upside down"
    assert File.exists?(sheet)
  end

  test "a hunt session is recorded and reported too", %{tmp_dir: tmp_dir} do
    {:ok, _, socket} =
      UserSocket
      |> socket()
      |> subscribe_and_join(IndoorsExperimentsWeb.HuntChannel, "hunt:recorder-test", %{
        "target" => "bus"
      })

    for i <- 0..4 do
      header = Jason.encode!(%{seq: i + 1, t: i * 125})

      ref =
        push(
          socket,
          "frame",
          {:binary, <<byte_size(header)::32, header::binary, jpeg("bus.jpg")::binary>>}
        )

      assert_reply ref, :ok, _, 5_000
    end

    Process.sleep(500)
    session = Path.join(tmp_dir, "latest")
    assert Path.wildcard(Path.join([session, "annotated", "*.jpg"])) != []

    {text, _sheet} = SessionReport.build(session)
    assert text =~ "(hunt)"
    assert text =~ "Scavenger hunt: 1 found"
    assert text =~ ~r/bus\s+FOUND/
    refute text =~ "Decision timeline"
  end
end
