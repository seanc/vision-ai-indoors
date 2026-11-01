defmodule Mix.Tasks.Vision.Report do
  @shortdoc "Summarises a recorded camera session"

  @moduledoc """
  Prints a summary of a recorded camera session and writes a contact sheet.

      mix vision.report                         # the newest session
      mix vision.report tmp/sessions/<folder>   # a specific one

  See `IndoorsExperiments.Vision.SessionReport` for what's in it.
  """

  use Mix.Task

  alias IndoorsExperiments.Vision.SessionReport

  @requirements ["app.config"]

  @impl true
  def run(args) do
    dir =
      case args do
        [dir | _] ->
          dir

        [] ->
          Path.join(
            Application.get_env(:indoors_experiments, :recordings_dir) || "tmp/sessions",
            "latest"
          )
      end

    if File.dir?(dir) do
      {text, _sheet} = SessionReport.build(dir)
      Mix.shell().info(text)
    else
      Mix.raise("No session folder at #{dir}. Open the camera page and start a session first.")
    end
  end
end
