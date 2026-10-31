defmodule ShubhVivahs.Photos.Detection do
  use Ecto.Schema
  import Ecto.Changeset

  # One face found in one photo. The box is in the web-sized copy's pixels.
  schema "photo_detections" do
    belongs_to(:photo, ShubhVivahs.Photos.Photo)
    belongs_to(:face, ShubhVivahs.Photos.Face)
    field(:bbox_x, :float)
    field(:bbox_y, :float)
    field(:bbox_w, :float)
    field(:bbox_h, :float)
    field(:confidence, :float)
    field(:embedding, ShubhVivahs.FaceDetection.Embedding)
    timestamps(type: :utc_datetime)
  end

  def changeset(detection, attrs) do
    detection
    |> cast(attrs, [
      :photo_id,
      :face_id,
      :bbox_x,
      :bbox_y,
      :bbox_w,
      :bbox_h,
      :confidence,
      :embedding
    ])
    |> validate_required([:photo_id, :face_id])
  end
end
