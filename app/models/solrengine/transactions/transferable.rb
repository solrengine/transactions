module Solrengine
  module Transactions
    module Transferable
      extend ActiveSupport::Concern

      SOLANA_ADDRESS_FORMAT = /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/
      SOLANA_SIGNATURE_FORMAT = /\A[1-9A-HJ-NP-Za-km-z]{86,88}\z/
      VALID_STATUSES = %w[pending submitted processed confirmed finalized failed].freeze
      MAX_LAMPORTS = 580_000_000_000_000_000

      included do
        belongs_to :user

        validates :recipient, presence: true,
          format: { with: SOLANA_ADDRESS_FORMAT, message: "is not a valid Solana address" }
        validates :amount_lamports, presence: true,
          numericality: { greater_than: 0, less_than_or_equal_to: MAX_LAMPORTS }
        validates :amount_sol, presence: true, numericality: { greater_than: 0 }
        validates :network, presence: true
        validates :status, presence: true, inclusion: { in: VALID_STATUSES }
        validates :signature, format: { with: SOLANA_SIGNATURE_FORMAT }, allow_nil: true

        scope :recent, -> { order(created_at: :desc).limit(10) }
      end

      def sol_amount_display
        amount_sol.to_f.round(6)
      end

      def short_signature
        return nil unless signature
        "#{signature[0..7]}...#{signature[-4..]}"
      end

      def short_recipient
        "#{recipient[0..3]}...#{recipient[-4..]}"
      end

      def confirmed?
        status == "confirmed" || status == "finalized"
      end

      def failed?
        status == "failed"
      end

      def pending?
        status == "pending" || status == "submitted"
      end
    end
  end
end
