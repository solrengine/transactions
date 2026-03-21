# frozen_string_literal: true

require "test_helper"

class TransferableTest < Minitest::Test
  def setup
    @user = User.create!(wallet_address: "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d")
  end

  def teardown
    Transfer.delete_all
    User.delete_all
  end

  def valid_attrs
    {
      user: @user,
      recipient: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
      amount_lamports: 1_000_000_000,
      amount_sol: 1.0,
      network: "mainnet",
      status: "pending"
    }
  end

  # --- Recipient validation ---

  def test_valid_transfer
    transfer = Transfer.new(valid_attrs)
    assert transfer.valid?, "Expected valid transfer, got: #{transfer.errors.full_messages}"
  end

  def test_rejects_missing_recipient
    transfer = Transfer.new(valid_attrs.merge(recipient: nil))
    refute transfer.valid?
    assert_includes transfer.errors[:recipient], "can't be blank"
  end

  def test_rejects_invalid_recipient_address
    invalid_addresses = [ "", "0x123", "not-a-solana-address!", "abc" ]
    invalid_addresses.each do |addr|
      transfer = Transfer.new(valid_attrs.merge(recipient: addr))
      refute transfer.valid?, "Expected #{addr.inspect} to be invalid"
    end
  end

  def test_accepts_valid_solana_addresses
    valid_addresses = [
      "11111111111111111111111111111111",
      "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
      "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    ]
    valid_addresses.each do |addr|
      transfer = Transfer.new(valid_attrs.merge(recipient: addr))
      assert transfer.valid?, "Expected #{addr} to be valid, got: #{transfer.errors.full_messages}"
    end
  end

  # --- Amount validation ---

  def test_rejects_zero_lamports
    transfer = Transfer.new(valid_attrs.merge(amount_lamports: 0))
    refute transfer.valid?
  end

  def test_rejects_negative_lamports
    transfer = Transfer.new(valid_attrs.merge(amount_lamports: -100))
    refute transfer.valid?
  end

  def test_rejects_lamports_exceeding_max_supply
    max = Solrengine::Transactions::Transferable::MAX_LAMPORTS
    transfer = Transfer.new(valid_attrs.merge(amount_lamports: max + 1))
    refute transfer.valid?
  end

  def test_accepts_max_lamports
    max = Solrengine::Transactions::Transferable::MAX_LAMPORTS
    transfer = Transfer.new(valid_attrs.merge(amount_lamports: max, amount_sol: max / 1_000_000_000.0))
    assert transfer.valid?, "Expected max lamports to be valid, got: #{transfer.errors.full_messages}"
  end

  def test_accepts_large_lamport_values
    # 100 SOL = 100_000_000_000 lamports (exceeds 32-bit int)
    lamports = 100_000_000_000
    transfer = Transfer.create!(valid_attrs.merge(amount_lamports: lamports, amount_sol: 100.0))
    transfer.reload
    assert_equal lamports, transfer.amount_lamports, "Lamports should survive roundtrip (bigint column)"
  end

  # --- Status validation ---

  def test_rejects_invalid_status
    transfer = Transfer.new(valid_attrs.merge(status: "bogus"))
    refute transfer.valid?
    assert_includes transfer.errors[:status], "is not included in the list"
  end

  def test_accepts_all_valid_statuses
    Solrengine::Transactions::Transferable::VALID_STATUSES.each do |status|
      transfer = Transfer.new(valid_attrs.merge(status: status))
      assert transfer.valid?, "Expected status '#{status}' to be valid, got: #{transfer.errors.full_messages}"
    end
  end

  # --- Signature validation ---

  def test_accepts_nil_signature
    transfer = Transfer.new(valid_attrs.merge(signature: nil))
    assert transfer.valid?
  end

  def test_rejects_invalid_signature_format
    transfer = Transfer.new(valid_attrs.merge(signature: "not-valid"))
    refute transfer.valid?
    assert_includes transfer.errors[:signature], "is invalid"
  end

  def test_accepts_valid_signature
    sig = "5VERv8NMHJyABFz2JNzRLxnLPfBY7jXTPa5Qx7z1oKzShMGheYAeHGRKNKJBh3AWELk8xNDPYEhvNEJxDXGKwmH"
    transfer = Transfer.new(valid_attrs.merge(signature: sig))
    assert transfer.valid?, "Expected valid signature, got: #{transfer.errors.full_messages}"
  end

  # --- Status predicates ---

  def test_confirmed_predicate
    transfer = Transfer.new(valid_attrs.merge(status: "confirmed"))
    assert transfer.confirmed?

    transfer.status = "finalized"
    assert transfer.confirmed?

    transfer.status = "pending"
    refute transfer.confirmed?
  end

  def test_failed_predicate
    transfer = Transfer.new(valid_attrs.merge(status: "failed"))
    assert transfer.failed?

    transfer.status = "pending"
    refute transfer.failed?
  end

  def test_pending_predicate
    transfer = Transfer.new(valid_attrs.merge(status: "pending"))
    assert transfer.pending?

    transfer.status = "submitted"
    assert transfer.pending?

    transfer.status = "confirmed"
    refute transfer.pending?
  end

  # --- Display helpers ---

  def test_sol_amount_display
    transfer = Transfer.new(valid_attrs.merge(amount_sol: 1.123456789))
    assert_equal 1.123457, transfer.sol_amount_display
  end

  def test_short_signature
    transfer = Transfer.new(valid_attrs.merge(signature: nil))
    assert_nil transfer.short_signature

    transfer.signature = "5VERv8NMHJyABFz2JNzRLxnLPfBY7jXTPa5Qx7z1oKzShMGheYAeHGRKNKJBh3AWELk8xNDPYEhvNEJxDXGKwmH"
    assert_equal "5VERv8NM...KwmH", transfer.short_signature
  end

  def test_short_recipient
    transfer = Transfer.new(valid_attrs)
    assert_equal "9WzD...AWWM", transfer.short_recipient
  end

  # --- Scope ---

  def test_recent_scope
    12.times do |i|
      Transfer.create!(valid_attrs.merge(created_at: i.days.ago))
    end
    assert_equal 10, Transfer.recent.count
    assert Transfer.recent.first.created_at > Transfer.recent.last.created_at
  end
end
