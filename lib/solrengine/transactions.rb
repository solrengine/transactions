require "solrengine/rpc"
require_relative "transactions/version"
require_relative "transactions/engine" if defined?(Rails::Engine)

module Solrengine
  module Transactions
    mattr_accessor :transfer_class, default: "Transfer"

    def self.transfer_model
      transfer_class.constantize
    end

    def self.configure
      yield self
    end
  end
end
