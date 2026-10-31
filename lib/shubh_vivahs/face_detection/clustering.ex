defmodule ShubhVivahs.FaceDetection.Clustering do
  @moduledoc """
  Groups face detections from a single video into unique identities.

  Each detection is a map that must include an `:embedding` (a list of
  floats, as produced by SFace). Processes detections in order,
  greedily assigning each one to the existing cluster whose running
  centroid it's most similar to — as long as that similarity clears
  `:threshold` — or starting a new cluster otherwise.

  This is deliberately *not* single-linkage clustering (merge whenever
  a detection matches *any* existing member). Single-linkage chains: if
  A matches B and B matches C, they all merge even when A and C aren't
  actually similar — which reliably collapses most of a real video's
  distinct people into one giant cluster once there are enough frames
  for a chain to form. Comparing against a stable running centroid
  instead avoids that chaining.
  """

  # SFace's documented same-identity cosine-similarity threshold.
  @default_threshold 0.363

  @doc """
  Clusters `detections` and returns a list of
  `%{centroid: [float], members: [detection, ...]}`, each a non-empty
  cluster in the order it was first seen. `members` preserves the
  input order.
  """
  def cluster(detections, opts \\ [])
  def cluster([], _opts), do: []

  def cluster(detections, opts) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)

    detections
    |> Enum.reduce([], fn detection, clusters -> assign(clusters, detection, threshold) end)
    |> Enum.reverse()
    |> Enum.map(fn cluster -> %{cluster | members: Enum.reverse(cluster.members)} end)
  end

  defp assign(clusters, detection, threshold) do
    case best_match(clusters, detection, threshold) do
      {:ok, index} -> List.update_at(clusters, index, &add_member(&1, detection))
      :error -> [new_cluster(detection) | clusters]
    end
  end

  defp best_match(clusters, detection, threshold) do
    clusters
    |> Enum.with_index()
    |> Enum.map(fn {cluster, index} ->
      {index, cosine_similarity(cluster.centroid, detection.embedding)}
    end)
    |> Enum.filter(fn {_index, similarity} -> similarity >= threshold end)
    |> case do
      [] ->
        :error

      matches ->
        {:ok, matches |> Enum.max_by(fn {_index, similarity} -> similarity end) |> elem(0)}
    end
  end

  defp new_cluster(detection) do
    %{centroid: detection.embedding, count: 1, members: [detection]}
  end

  defp add_member(%{centroid: centroid, count: count, members: members}, detection) do
    new_count = count + 1

    updated_centroid =
      Enum.zip_with(centroid, detection.embedding, fn c, e -> c + (e - c) / new_count end)

    %{centroid: updated_centroid, count: new_count, members: [detection | members]}
  end

  defp cosine_similarity(a, b) do
    dot = a |> Enum.zip(b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
    dot / (norm(a) * norm(b))
  end

  defp norm(vector) do
    vector
    |> Enum.reduce(0.0, fn x, acc -> acc + x * x end)
    |> :math.sqrt()
  end
end
