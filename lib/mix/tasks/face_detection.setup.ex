defmodule Mix.Tasks.FaceDetection.Setup do
  @moduledoc """
  Downloads and sha256-verifies the assets the face detection service
  needs, into gitignored `priv/face_detection/{models,bin}/`:

    * the YuNet face-detection and SFace face-embedding ONNX models
    * a static `ffmpeg` binary — only if no `ffmpeg` is already on PATH,
      since Evision's precompiled OpenCV build can't decode video itself

  Not part of the base `mix setup` alias since most contributors won't
  need these ~80MB of assets.
  """

  use Mix.Task

  @shortdoc "Downloads face detection models (and ffmpeg, if needed)"

  @models [
    %{
      url:
        "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx",
      sha256: "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4",
      dest: "priv/face_detection/models/face_detection_yunet_2023mar.onnx"
    },
    %{
      url:
        "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx",
      sha256: "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79",
      dest: "priv/face_detection/models/face_recognition_sface_2021dec.onnx"
    }
  ]

  @ffmpeg_tarball_url "https://johnvansickle.com/ffmpeg/old-releases/ffmpeg-6.0.1-amd64-static.tar.xz"
  @ffmpeg_tarball_sha256 "28268bf402f1083833ea269331587f60a242848880073be8016501d864bd07a5"
  @ffmpeg_dest "priv/face_detection/bin/ffmpeg"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start", ["--no-start"])
    Application.ensure_all_started(:req)

    Enum.each(@models, &fetch_model/1)
    ensure_ffmpeg()
  end

  defp fetch_model(%{url: url, sha256: sha256, dest: dest}) do
    if up_to_date?(dest, sha256) do
      Mix.shell().info("#{dest} already present, skipping")
    else
      Mix.shell().info("Downloading #{url}")
      body = Req.get!(url, redirect: true).body
      verify!(body, sha256, url)
      File.mkdir_p!(Path.dirname(dest))
      File.write!(dest, body)
      Mix.shell().info("Wrote #{dest}")
    end
  end

  defp ensure_ffmpeg do
    cond do
      System.find_executable("ffmpeg") ->
        Mix.shell().info("System ffmpeg found, skipping bundled ffmpeg download")

      File.regular?(@ffmpeg_dest) ->
        Mix.shell().info("#{@ffmpeg_dest} already present, skipping")

      true ->
        Mix.shell().info("Downloading #{@ffmpeg_tarball_url}")
        body = Req.get!(@ffmpeg_tarball_url, redirect: true).body
        verify!(body, @ffmpeg_tarball_sha256, @ffmpeg_tarball_url)
        extract_ffmpeg_binary!(body)
        Mix.shell().info("Wrote #{@ffmpeg_dest}")
    end
  end

  defp extract_ffmpeg_binary!(tarball) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "shubh_vivahs_ffmpeg_setup_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    tarball_path = Path.join(tmp_dir, "ffmpeg.tar.xz")
    File.write!(tarball_path, tarball)

    {_output, 0} = System.cmd("tar", ["-xJf", tarball_path, "-C", tmp_dir])

    [binary_path] = Path.wildcard(Path.join(tmp_dir, "*/ffmpeg"))
    File.mkdir_p!(Path.dirname(@ffmpeg_dest))
    File.cp!(binary_path, @ffmpeg_dest)
    File.chmod!(@ffmpeg_dest, 0o755)
    File.rm_rf!(tmp_dir)
  end

  defp up_to_date?(dest, sha256) do
    File.regular?(dest) and file_sha256(dest) == sha256
  end

  defp file_sha256(path), do: path |> File.read!() |> sha256_hex()

  defp verify!(binary, expected_sha256, url) do
    actual = sha256_hex(binary)

    if actual != expected_sha256 do
      Mix.raise("""
      Checksum mismatch downloading #{url}
      expected: #{expected_sha256}
      actual:   #{actual}
      """)
    end
  end

  defp sha256_hex(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
end
