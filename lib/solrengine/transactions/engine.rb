module Solrengine
  module Transactions
    class Engine < ::Rails::Engine
      isolate_namespace Solrengine::Transactions

      initializer "solrengine-transactions.assets" do |app|
        app.config.assets.paths << root.join("app/assets/javascripts")
      end
    end
  end
end
