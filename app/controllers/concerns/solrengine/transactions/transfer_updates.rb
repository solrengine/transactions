module Solrengine
  module Transactions
    module TransferUpdates
      extend ActiveSupport::Concern

      ALLOWED_TRANSITIONS = {
        "pending" => %w[submitted],
        "submitted" => %w[processed confirmed finalized failed]
      }.freeze

      private

      def find_user_transfer
        current_user.transfers.find(params[:id])
      end

      def valid_status_transition?(transfer, new_status)
        ALLOWED_TRANSITIONS.fetch(transfer.status, []).include?(new_status)
      end
    end
  end
end
