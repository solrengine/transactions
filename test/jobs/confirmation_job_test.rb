# frozen_string_literal: true

require "test_helper"
require "solrengine/transactions/confirmation_job"

class ConfirmationJobTest < Minitest::Test
  def setup
    @user = User.create!(wallet_address: "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d")
    @transfer = Transfer.create!(
      user: @user,
      recipient: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
      amount_lamports: 1_000_000_000,
      amount_sol: 1.0,
      network: "mainnet",
      status: "submitted",
      signature: "5VERv8NMHJyABFz2JNzRLxnLPfBY7jXTPa5Qx7z1oKzShMGheYAeHGRKNKJBh3AWELk8xNDPYEhvNEJxDXGKwmH"
    )
    @rpc_client = StubRpcClient.new
    Solrengine::Rpc.test_client = @rpc_client
    ActiveJob::Base.queue_adapter = :test
  end

  def teardown
    Transfer.delete_all
    User.delete_all
    Solrengine::Rpc.test_client = nil
  end

  def perform_job(transfer_id = @transfer.id, attempt: 0)
    Solrengine::Transactions::ConfirmationJob.new.perform(transfer_id, attempt: attempt)
  end

  # --- Basic behavior ---

  def test_skips_if_transfer_not_found
    assert_nil perform_job(999_999)
  end

  def test_skips_if_no_signature
    @transfer.update_column(:signature, nil)
    assert_nil perform_job
  end

  def test_skips_if_already_confirmed
    @transfer.update_column(:status, "finalized")
    assert_nil perform_job
  end

  def test_skips_if_already_failed
    @transfer.update_column(:status, "failed")
    assert_nil perform_job
  end

  # --- Status transitions ---

  def test_sets_finalized_status
    @rpc_client.status_response = { "confirmationStatus" => "finalized" }
    perform_job
    @transfer.reload
    assert_equal "finalized", @transfer.status
  end

  def test_sets_confirmed_status
    @rpc_client.status_response = { "confirmationStatus" => "confirmed" }
    perform_job
    @transfer.reload
    assert_equal "confirmed", @transfer.status
  end

  def test_sets_processed_status_and_re_enqueues
    @rpc_client.status_response = { "confirmationStatus" => "processed" }
    perform_job
    @transfer.reload
    assert_equal "processed", @transfer.status
    assert_enqueued_jobs 1, queue: "solana_confirmation"
  end

  def test_rejects_invalid_confirmation_status
    @rpc_client.status_response = { "confirmationStatus" => "bogus_status" }
    perform_job
    @transfer.reload
    assert_equal "confirmed", @transfer.status, "Invalid RPC status should fall back to 'confirmed'"
  end

  def test_sets_failed_on_rpc_error
    @rpc_client.status_response = { "err" => { "InstructionError" => [ 0, "InsufficientFunds" ] } }
    perform_job
    @transfer.reload
    assert_equal "failed", @transfer.status
    assert @transfer.error_message.present?
  end

  def test_truncates_long_error_messages
    long_error = "x" * 1000
    @rpc_client.status_response = { "err" => long_error }
    perform_job
    @transfer.reload
    assert @transfer.error_message.length <= 500
  end

  # --- Retry behavior ---

  def test_re_enqueues_when_status_nil
    @rpc_client.status_response = nil
    perform_job(attempt: 0)
    assert_enqueued_jobs 1, queue: "solana_confirmation"
  end

  def test_fails_after_max_attempts
    @rpc_client.status_response = nil
    perform_job(attempt: Solrengine::Transactions::ConfirmationJob::MAX_ATTEMPTS)
    @transfer.reload
    assert_equal "failed", @transfer.status
    assert_match(/not confirmed/, @transfer.error_message)
  end

  def test_does_not_re_enqueue_on_finalized
    @rpc_client.status_response = { "confirmationStatus" => "finalized" }
    perform_job
    assert_enqueued_jobs 0, queue: "solana_confirmation"
  end

  def test_re_enqueues_on_confirmed_for_finalization
    @rpc_client.status_response = { "confirmationStatus" => "confirmed" }
    perform_job
    assert_enqueued_jobs 1, queue: "solana_confirmation"
  end

  # --- RPC error handling ---

  def test_handles_rpc_error_gracefully
    def @rpc_client.get_signature_status(_sig)
      raise StandardError, "connection refused"
    end
    # Should not raise
    perform_job(attempt: 0)
    @transfer.reload
    assert_equal "submitted", @transfer.status, "Status should not change on RPC error"
  end

  # --- Configurable model ---

  def test_uses_configured_transfer_class
    original = Solrengine::Transactions.transfer_class
    Solrengine::Transactions.transfer_class = "Transfer"
    assert_equal Transfer, Solrengine::Transactions.transfer_model
  ensure
    Solrengine::Transactions.transfer_class = original
  end

  private

  def assert_enqueued_jobs(count, queue: nil)
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
    jobs = jobs.select { |j| j[:queue] == queue } if queue
    assert_equal count, jobs.size, "Expected #{count} enqueued job(s) on #{queue || 'any'} queue, got #{jobs.size}"
  end
end
