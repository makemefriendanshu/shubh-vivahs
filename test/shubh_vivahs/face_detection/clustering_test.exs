defmodule ShubhVivahs.FaceDetection.ClusteringTest do
  use ExUnit.Case, async: true

  alias ShubhVivahs.FaceDetection.Clustering

  describe "cluster/2" do
    test "returns an empty list for no detections" do
      assert Clustering.cluster([]) == []
    end

    test "a single detection forms its own cluster" do
      detection = %{label: :a, embedding: [1.0, 0.0, 0.0, 0.0]}
      assert [%{members: [^detection]}] = Clustering.cluster([detection])
    end

    test "merges near-identical embeddings and keeps dissimilar ones apart" do
      detections = [
        %{label: :a1, embedding: [1.0, 0.0, 0.0, 0.0]},
        %{label: :a2, embedding: [0.98, 0.02, 0.0, 0.0]},
        %{label: :b1, embedding: [0.0, 1.0, 0.0, 0.0]},
        %{label: :b2, embedding: [0.02, 0.98, 0.0, 0.0]}
      ]

      clusters = Clustering.cluster(detections)

      assert labels_by_cluster(clusters) == [[:a1, :a2], [:b1, :b2]]
    end

    test "a stricter threshold can split an otherwise-merged pair" do
      detections = [
        %{label: :a1, embedding: [1.0, 0.0, 0.0, 0.0]},
        %{label: :a2, embedding: [0.9, 0.436, 0.0, 0.0]}
      ]

      assert labels_by_cluster(Clustering.cluster(detections)) == [[:a1, :a2]]
      assert labels_by_cluster(Clustering.cluster(detections, threshold: 0.99)) == [[:a1], [:a2]]
    end

    test "does not chain: A~B and B~C similar but A~C dissimilar stays two clusters" do
      # Unit vectors 68 degrees apart (just over the 0.363 cosine threshold
      # between adjacent pairs), so A-B and B-C each clear the threshold,
      # but A-C (136 degrees apart) does not. Single-linkage would merge
      # all three transitively through B; comparing against a running
      # centroid instead should keep A/B together and leave C on its own.
      a = %{label: :a, embedding: [1.0, 0.0]}

      b = %{
        label: :b,
        embedding: [:math.cos(68 * :math.pi() / 180), :math.sin(68 * :math.pi() / 180)]
      }

      c = %{
        label: :c,
        embedding: [:math.cos(136 * :math.pi() / 180), :math.sin(136 * :math.pi() / 180)]
      }

      assert labels_by_cluster(Clustering.cluster([a, b, c])) == [[:a, :b], [:c]]
    end

    test "a cluster's centroid is the running mean of its members' embeddings" do
      detections = [
        %{label: :a1, embedding: [1.0, 1.0]},
        %{label: :a2, embedding: [3.0, 3.0]}
      ]

      assert [%{centroid: [2.0, 2.0]}] = Clustering.cluster(detections)
    end
  end

  defp labels_by_cluster(clusters) do
    clusters
    |> Enum.map(fn cluster -> cluster.members |> Enum.map(& &1.label) |> Enum.sort() end)
    |> Enum.sort()
  end
end
