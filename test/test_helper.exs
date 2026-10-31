# One test module at a time: the test database is SQLite, which allows a
# single writer, and parallel modules that write kept failing with
# "Database busy" under load. The suite takes a few seconds either way.
ExUnit.start(exclude: [:face_detection_models], max_cases: 1)

Ecto.Adapters.SQL.Sandbox.mode(ShubhVivahs.Repo, :manual)
