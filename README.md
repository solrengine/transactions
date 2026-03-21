# SolRengine Transactions

SOL transfer model, confirmation tracking, and Stimulus controller for Rails. Build transactions with @solana/kit, sign with wallet-standard, track confirmation via background job.

Part of the [SolRengine](https://github.com/solrengine) framework.

## Install

```ruby
gem "solrengine-transactions"
```

```bash
rails generate solrengine:transactions:install
rails db:prepare
```

## Configuration

```ruby
# config/initializers/solrengine.rb
Solrengine::Transactions.configure do |config|
  config.transfer_class = "Transfer" # default, change if your model is named differently
end
```

## Usage

### Model

```ruby
class Transfer < ApplicationRecord
  include Solrengine::Transactions::Transferable
end
```

### Confirmation Job

```ruby
Solrengine::Transactions::ConfirmationJob.perform_later(transfer.id)
```

The job uses the `solana_confirmation` queue. Configure your queue adapter accordingly:

```ruby
# config/sidekiq.yml
:queues:
  - default
  - solana_confirmation
```

### Controller Authorization

Include `TransferUpdates` in your transfers controller to enforce ownership and valid status transitions:

```ruby
class TransfersController < ApplicationController
  include Solrengine::Transactions::TransferUpdates

  def update
    transfer = find_user_transfer # scopes to current_user

    unless valid_status_transition?(transfer, params[:status])
      return head :unprocessable_entity
    end

    transfer.update!(signature: params[:signature], status: params[:status])
    head :ok
  end
end
```

**Important:** Always scope transfer lookups to the current user. Never allow unauthenticated access to transfer updates. Validate the transfer amount against the on-chain balance in your `create` action.

### Stimulus Controller

The controller expects these data attributes:

```html
<div data-controller="transfer"
     data-transfer-create-url-value="/transfers"
     data-transfer-dashboard-url-value="/dashboard"
     data-transfer-wallet-value="<%= current_user.wallet_address %>"
     data-transfer-balance-value="<%= @balance %>"
     data-transfer-rpc-url-value="<%= Solrengine::Rpc.endpoint %>"
     data-transfer-chain-value="solana:devnet"
     data-transfer-transfers-path-value="/transfers">
```

The `chain` value must be one of `solana:mainnet`, `solana:devnet`, or `solana:testnet`. The `transfers-path` value defaults to `/transfers`.

Your server's create endpoint must return `last_valid_block_height` from the `getLatestBlockhash` RPC response:

```json
{
  "transfer_id": 1,
  "sender": "...",
  "recipient": "...",
  "amount_lamports": 1000000000,
  "blockhash": "...",
  "last_valid_block_height": 123456789
}
```

## License

MIT
