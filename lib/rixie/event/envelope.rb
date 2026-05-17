# frozen_string_literal: true

module Rixie
  module Event
    Envelope = Data.define(:event, :occurred_at, :session_id, :task_id, :run_id, :sequence_number, :event_id)
  end
end
