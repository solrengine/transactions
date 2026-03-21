module Solrengine
  module Transactions
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file "migration.rb", "db/migrate/#{timestamp}_create_transfers.rb"
      end

      def create_transfer_model
        create_file "app/models/transfer.rb", <<~RUBY
          class Transfer < ApplicationRecord
            include Solrengine::Transactions::Transferable
          end
        RUBY
      end

      def show_post_install
        say "\n  SolRengine Transactions installed!", :green
        say "  Run `rails db:migrate` to create the transfers table.\n\n"
      end
    end
  end
end
