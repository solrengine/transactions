module Solrengine
  module Transactions
    class ConfirmationJob < ActiveJob::Base
      queue_as :solana_confirmation

      MAX_ATTEMPTS = 30
      BACKOFF_SCHEDULE = [ 2, 4, 8, 8, 8 ].freeze

      def perform(transfer_id, attempt: 0)
        transfer = Solrengine::Transactions.transfer_model
          .lock
          .includes(:user)
          .find_by(id: transfer_id)
        return unless transfer&.signature
        return if transfer.confirmed? || transfer.failed?

        status_info = fetch_status(transfer.signature)

        if status_info.nil?
          if attempt < MAX_ATTEMPTS
            self.class.set(wait: wait_for(attempt)).perform_later(transfer_id, attempt: attempt + 1)
          else
            transfer.update!(status: "failed", error_message: "Transaction not confirmed after #{MAX_ATTEMPTS} attempts")
            broadcast_status(transfer)
          end
          return
        end

        if status_info["err"]
          transfer.update!(status: "failed", error_message: status_info["err"].to_s.truncate(500))
        else
          confirmation = status_info["confirmationStatus"]
          new_status = Transferable::VALID_STATUSES.include?(confirmation) ? confirmation : "confirmed"
          transfer.update!(status: new_status)

          if confirmation == "processed" || confirmation == "confirmed"
            self.class.set(wait: wait_for(attempt)).perform_later(transfer_id, attempt: attempt + 1)
          end
        end

        broadcast_status(transfer)
      end

      private

      def fetch_status(signature)
        Solrengine::Rpc.client.get_signature_status(signature)
      rescue => e
        Rails.logger.error("[Solrengine::Transactions] RPC error: #{e.message}")
        nil
      end

      def wait_for(attempt)
        (BACKOFF_SCHEDULE[attempt] || BACKOFF_SCHEDULE.last).seconds
      end

      def broadcast_status(transfer)
        return unless defined?(Turbo::StreamsChannel)

        Turbo::StreamsChannel.broadcast_replace_to(
          "user_transfers_#{transfer.user_id}",
          target: "transfer_status_#{transfer.id}",
          partial: "transfers/status",
          locals: { transfer: transfer }
        )
      end
    end
  end
end
