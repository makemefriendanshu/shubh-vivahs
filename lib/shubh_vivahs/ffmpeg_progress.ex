defmodule ShubhVivahs.FFmpegProgress do
  @moduledoc """
  Runs ffmpeg and reports how far through the input it is, by reading
  its `-progress` output line by line instead of waiting for it to exit
  (`System.cmd/3` only returns once ffmpeg is done). The total duration
  comes from ffmpeg's own "Duration:" line for the input, so callers
  don't need to probe the file first.
  """

  @doc """
  Runs `ffmpeg` with `args` (output options and destination included),
  calling `on_progress.(fraction)` as it goes. Returns `{output, exit_status}`
  like `System.cmd/3`, where `output` is ffmpeg's log minus progress lines.
  """
  @spec run(String.t(), [String.t()], (float -> any)) :: {String.t(), non_neg_integer}
  def run(ffmpeg, args, on_progress) do
    port =
      Port.open({:spawn_executable, ffmpeg}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 8192},
        args: ["-hide_banner", "-nostats", "-progress", "pipe:1" | args]
      ])

    collect(port, on_progress, nil, [])
  end

  defp collect(port, on_progress, duration_ms, log) do
    receive do
      {^port, {:data, {_eol, line}}} ->
        cond do
          String.starts_with?(line, "out_time_us=") ->
            report(line, duration_ms, on_progress)
            collect(port, on_progress, duration_ms, log)

          progress_line?(line) ->
            collect(port, on_progress, duration_ms, log)

          true ->
            collect(port, on_progress, duration_ms || parse_duration(line), [
              line | Enum.take(log, 199)
            ])
        end

      {^port, {:exit_status, status}} ->
        {log |> Enum.reverse() |> Enum.join("\n"), status}
    end
  end

  defp report(_line, nil, _on_progress), do: :ok

  defp report("out_time_us=" <> value, duration_ms, on_progress) do
    case Integer.parse(value) do
      {us, _} when us >= 0 -> on_progress.(min(us / 1000 / duration_ms, 1.0))
      _ -> :ok
    end
  end

  @progress_keys ~w(frame fps stream_ bitrate total_size out_time speed dup_frames drop_frames progress)
  defp progress_line?(line), do: Enum.any?(@progress_keys, &String.starts_with?(line, &1))

  defp parse_duration(line) do
    case Regex.run(~r/Duration: (\d+):(\d{2}):(\d{2})\.(\d{2})/, line) do
      [_, h, m, s, cs] ->
        ms =
          (String.to_integer(h) * 3600 + String.to_integer(m) * 60 + String.to_integer(s)) * 1000 +
            String.to_integer(cs) * 10

        if ms > 0, do: ms

      nil ->
        nil
    end
  end
end
