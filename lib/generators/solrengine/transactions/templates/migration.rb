class CreateTransfers < ActiveRecord::Migration[7.1]
  def change
    create_table :transfers do |t|
      t.references :user, null: false, foreign_key: true
      t.string :signature
      t.string :recipient, null: false
      t.bigint :amount_lamports, null: false
      t.decimal :amount_sol, null: false
      t.string :network, null: false, default: "mainnet"
      t.string :status, null: false, default: "pending"
      t.text :error_message

      t.timestamps
    end
    add_index :transfers, :signature, unique: true
    add_index :transfers, :status
    add_index :transfers, [ :user_id, :created_at ]
  end
end
