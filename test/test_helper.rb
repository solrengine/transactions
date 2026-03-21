# frozen_string_literal: true

require "minitest/autorun"
require "active_record"
require "active_job"
require "active_support"

$LOAD_PATH.unshift File.expand_path("../app/models", __dir__)
$LOAD_PATH.unshift File.expand_path("../app/jobs", __dir__)
$LOAD_PATH.unshift File.expand_path("../app/controllers/concerns", __dir__)

require "solrengine/transactions"
require "solrengine/transactions/transferable"

# In-memory SQLite database
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = Logger.new(nil)

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :wallet_address
    t.timestamps
  end

  create_table :transfers, force: true do |t|
    t.references :user, null: false
    t.string :signature
    t.string :recipient, null: false
    t.bigint :amount_lamports, null: false
    t.decimal :amount_sol, null: false
    t.string :network, null: false, default: "mainnet"
    t.string :status, null: false, default: "pending"
    t.text :error_message
    t.timestamps
  end
end

class User < ActiveRecord::Base
  has_many :transfers
end

class Transfer < ActiveRecord::Base
  include Solrengine::Transactions::Transferable
end

# Configure ActiveJob for testing
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil)

# Configure Solrengine::Transactions
Solrengine::Transactions.transfer_class = "Transfer"

# Stub Rails.logger for tests outside full Rails environment
unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
  module Rails
    def self.logger
      @logger ||= Logger.new(nil)
    end
  end
end

# Stub RPC client for tests
class StubRpcClient
  attr_accessor :status_response

  def get_signature_status(_signature)
    status_response
  end
end

# Override Solrengine::Rpc.client for test isolation
module Solrengine
  module Rpc
    class << self
      attr_writer :test_client

      remove_method :client if method_defined?(:client)

      def client
        @test_client || super
      end
    end
  end
end
