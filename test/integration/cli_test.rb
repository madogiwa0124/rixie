# frozen_string_literal: true

require_relative "test_helper"
require "rixie/cli"

class CLIIntegrationTest < Integration::TestCase
  def test_starts_and_exits_on_eof
    cli = Rixie::CLI.new([])

    Rixie::CLI::Terminal.stub(:enable_stdout_router, nil) do
      Reline.stub(:readline, nil) do
        capture_io do
          cli.stub(:build_session, Object.new) do
            cli.run
          end
        end
      end
    end

    assert_equal "simple", cli.strategy_name
  end

  # -- register_command --

  def test_register_command_adds_to_extra_commands
    klass = stub_command_class("extra")
    Rixie::CLI.register_command(klass)
    assert_includes Rixie::CLI.extra_commands, klass
  ensure
    Rixie::CLI.reset_registered_commands!
  end

  def test_register_command_deduplicates
    klass = stub_command_class("extra")
    Rixie::CLI.register_command(klass)
    Rixie::CLI.register_command(klass)
    assert_equal 1, Rixie::CLI.extra_commands.count(klass)
  ensure
    Rixie::CLI.reset_registered_commands!
  end

  def test_reset_registered_commands_clears_registry
    Rixie::CLI.register_command(stub_command_class("extra"))
    Rixie::CLI.reset_registered_commands!
    assert_empty Rixie::CLI.extra_commands
  end

  def test_register_command_returns_cli_class_for_chaining
    klass = stub_command_class("extra")
    assert_equal Rixie::CLI, Rixie::CLI.register_command(klass)
  ensure
    Rixie::CLI.reset_registered_commands!
  end

  # -- Finished[content: nil] (return_direct path) --

  def test_handle_input_with_return_direct_completes_without_hanging
    inputs = ["hello", nil]
    fake_session = build_fake_session([Rixie::Event::Finished.new(content: nil)])

    cli = Rixie::CLI.new([])
    Rixie::CLI::Terminal.stub(:enable_stdout_router, nil) do
      Reline.stub(:readline, ->(_p, _h) { inputs.shift }) do
        capture_io do
          cli.stub(:build_session, fake_session) do
            cli.run
          end
        end
      end
    end
  end

  def test_cli_store_defaults_to_file_store_when_config_store_is_nil
    cli = Rixie::CLI.new([])
    Rixie.configure { |c| c.store = nil }

    assert_instance_of Rixie::Store::File, cli.send(:cli_store)
  end

  def test_resume_option_loads_selected_session_via_session_resume
    cli = Rixie::CLI.new(["-r"])
    fake_store = Object.new
    fake_store.define_singleton_method(:list_sessions) do |limit: nil|
      [Rixie::Store::Row.new(session_id: "sess-1", created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z", entry_count: 2, preview: "hello")]
    end

    fake_session = build_fake_session([])
    captured = nil
    inputs = ["1", nil]

    Reline.stub(:readline, ->(_p, _h) { inputs.shift }) do
      cli.stub(:cli_store, fake_store) do
        Rixie::Session.stub(:resume, ->(**kwargs) {
          captured = kwargs
          fake_session
        }) do
          capture_io { cli.run }
        end
      end
    end

    refute_nil captured
    assert_equal "sess-1", captured[:session_id]
    assert_same fake_store, captured[:store]
  end

  def test_resume_option_falls_back_to_new_session_when_no_saved_sessions_exist
    cli = Rixie::CLI.new(["-r"])
    fake_store = Object.new
    fake_store.define_singleton_method(:list_sessions) { |limit: nil| [] }

    fresh_session = build_fake_session([])

    Reline.stub(:readline, nil) do
      cli.stub(:cli_store, fake_store) do
        cli.stub(:build_session, fresh_session) do
          capture_io { cli.run }
        end
      end
    end
  end

  private

  def stub_command_class(command_name)
    Class.new(Rixie::CLI::Commands::Base) do
      define_method(:name) { command_name }
      def description = "stub"
      def call(_arg, cli:) = nil
    end
  end

  def build_fake_session(events)
    fake = Object.new
    envelopes = events.map.with_index(1) do |event, i|
      Rixie::Event::Envelope.new(
        event:, occurred_at: Time.now,
        session_id: nil, task_id: nil, run_id: nil,
        sequence_number: i, event_id: SecureRandom.uuid
      )
    end
    fake.define_singleton_method(:live) { |_input, **_kwargs| envelopes }
    fake.define_singleton_method(:context) { [] }
    fake
  end
end
