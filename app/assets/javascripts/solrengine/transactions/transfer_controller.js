import { Controller } from "@hotwired/stimulus"
import { getWallets } from "@wallet-standard/app"
import { SolanaSignAndSendTransaction } from "@solana/wallet-standard-features"
import {
  pipe,
  createTransactionMessage,
  setTransactionMessageLifetimeUsingBlockhash,
  setTransactionMessageFeePayer,
  appendTransactionMessageInstruction,
  compileTransaction,
  getBase64EncodedWireTransaction,
  address,
  getBase58Decoder,
} from "@solana/kit"

export default class extends Controller {
  static targets = ["recipient", "amount", "sendBtn", "status", "confirming", "confirmingText", "success", "solscanLink", "confirmationBadge"]
  static values = {
    createUrl: String,
    dashboardUrl: String,
    wallet: String,
    balance: Number,
    rpcUrl: String,
    chain: { type: String, default: "solana:mainnet" },
    transfersPath: { type: String, default: "/transfers" }
  }

  initialize() {
    this.walletStandard = null
    this.walletAccount = null
    this.isSending = false
    this.cancelToken = { canceled: false }
  }

  connect() {
    this.cancelToken = { canceled: false }
  }

  disconnect() {
    this.cancelToken.canceled = true
    if (this.redirectTimeout) clearTimeout(this.redirectTimeout)
  }

  async ensureConnected() {
    if (this.walletAccount?.address === this.walletValue) return
    if (this._connectingPromise) return this._connectingPromise
    this._connectingPromise = this._doConnect()
    try {
      return await this._connectingPromise
    } finally {
      this._connectingPromise = null
    }
  }

  async _doConnect() {
    const { get } = getWallets()
    for (const wallet of get()) {
      if (!wallet.features[SolanaSignAndSendTransaction]) continue

      const match = wallet.accounts.find(a => a.address === this.walletValue)
      if (match) {
        this.walletStandard = wallet
        this.walletAccount = match
        return
      }

      const connectFeature = wallet.features["standard:connect"]
      if (connectFeature) {
        try {
          const { accounts } = await connectFeature.connect()
          const found = accounts?.find(a => a.address === this.walletValue)
          if (found) {
            this.walletStandard = wallet
            this.walletAccount = found
            return
          }
        } catch { /* try next wallet */ }
      }
    }

    throw new Error(
      `Active wallet account doesn't match your login address (${this.walletValue.slice(0, 4)}...${this.walletValue.slice(-4)}). ` +
      `Please switch to the correct account in your wallet and try again.`
    )
  }

  setMax() {
    const max = Math.max(0, this.balanceValue - 0.005)
    this.amountTarget.value = max.toFixed(6)
  }

  async send() {
    if (this.isSending) return
    this.isSending = true

    try {
      const recipient = this.recipientTarget.value.trim()
      const amountSol = parseFloat(this.amountTarget.value)

      if (!recipient.match(/^[1-9A-HJ-NP-Za-km-z]{32,44}$/)) {
        return this.showStatus("Invalid recipient address", "error")
      }
      if (isNaN(amountSol) || amountSol <= 0) {
        return this.showStatus("Enter a valid amount", "error")
      }
      if (amountSol > this.balanceValue - 0.005) {
        return this.showStatus("Insufficient balance (need ~0.005 SOL for fees)", "error")
      }

      this.sendBtnTarget.disabled = true
      this.sendBtnTarget.textContent = "Preparing..."

      await this.ensureConnected()

      // Get transaction params from Rails
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const createResponse = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ recipient, amount_sol: amountSol })
      })

      if (!createResponse.ok) {
        const error = await createResponse.json()
        throw new Error(error.error || "Failed to prepare transaction")
      }

      const txParams = await createResponse.json()

      // Build and sign the transaction
      this.showConfirming("Sign the transaction in your wallet...")
      const txBytes = this.buildTransaction(txParams)

      const feature = this.walletStandard.features[SolanaSignAndSendTransaction]

      const [{ signature: sigBytes }] = await feature.signAndSendTransaction({
        account: this.walletAccount,
        transaction: txBytes,
        chain: this.chainValue
      })

      const decoder = getBase58Decoder()
      const signature = decoder.decode(sigBytes)

      // Report signature to server. The transaction is already on-chain,
      // so a server error must not hide the successful send from the user.
      this.confirmingTextTarget.textContent = "Confirming transaction..."
      try {
        await fetch(`${this.transfersPathValue}/${txParams.transfer_id}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
          body: JSON.stringify({ signature, status: "submitted" })
        })
      } catch (patchError) {
        console.error("Failed to report signature to server:", patchError)
      }

      this.showSuccess(signature, txParams.transfer_id)

    } catch (error) {
      console.error("Transfer error:", error)
      if (error.message?.includes("User rejected") || error.message?.includes("cancelled")) {
        this.showStatus("Transaction cancelled", "warning")
      } else {
        this.showStatus(error.message || "Transaction failed", "error")
      }
      this.resetSendBtn()
    } finally {
      this.isSending = false
    }
  }

  buildTransaction(txParams) {
    const lamportsBI = BigInt(txParams.amount_lamports)
    const data = new Uint8Array(12)
    const dv = new DataView(data.buffer)
    dv.setUint32(0, 2, true) // SystemProgram.transfer = index 2
    dv.setUint32(4, Number(lamportsBI & 0xFFFFFFFFn), true)
    dv.setUint32(8, Number(lamportsBI >> 32n), true)

    const instruction = {
      programAddress: address("11111111111111111111111111111111"),
      accounts: [
        { address: address(txParams.sender), role: 3 },    // writable signer
        { address: address(txParams.recipient), role: 1 },  // writable
      ],
      data: data
    }

    const txMessage = pipe(
      createTransactionMessage({ version: 0 }),
      tx => setTransactionMessageFeePayer(address(txParams.sender), tx),
      tx => setTransactionMessageLifetimeUsingBlockhash(
        { blockhash: txParams.blockhash, lastValidBlockHeight: BigInt(txParams.last_valid_block_height) },
        tx
      ),
      tx => appendTransactionMessageInstruction(instruction, tx),
    )

    const compiled = compileTransaction(txMessage)
    const base64 = getBase64EncodedWireTransaction(compiled)
    return Uint8Array.from(atob(base64), c => c.charCodeAt(0))
  }

  showConfirming(text) {
    this.sendBtnTarget.classList.add("hidden")
    this.confirmingTarget.classList.remove("hidden")
    this.confirmingTextTarget.textContent = text
  }

  showSuccess(signature, transferId) {
    this.confirmingTarget.classList.add("hidden")
    this.successTarget.classList.remove("hidden")

    const isDevnet = this.chainValue === "solana:devnet"
    const isTestnet = this.chainValue === "solana:testnet"

    const txUrl = (isDevnet || isTestnet)
      ? `https://explorer.solana.com/tx/${signature}?cluster=${isDevnet ? "devnet" : "testnet"}`
      : `https://solscan.io/tx/${signature}`

    this.solscanLinkTarget.href = txUrl
    this.solscanLinkTarget.textContent = signature.slice(0, 8) + "..." + signature.slice(-4)

    this.confirmationBadgeTarget.textContent = "Submitted"
    this.confirmationBadgeTarget.className = "inline-block px-2 py-1 rounded-full text-xs bg-yellow-900/30 text-yellow-400"

    this.pollStatus(transferId)
  }

  async pollStatus(transferId) {
    const token = this.cancelToken
    for (let i = 0; i < 30; i++) {
      await new Promise(r => setTimeout(r, 2000))
      if (token.canceled) return
      try {
        const res = await fetch(`${this.transfersPathValue}/${transferId}/status`)
        if (token.canceled) return
        const data = await res.json()
        if (data.status === "finalized" || data.status === "confirmed") {
          this.confirmationBadgeTarget.textContent = data.status.charAt(0).toUpperCase() + data.status.slice(1)
          this.confirmationBadgeTarget.className = "inline-block px-2 py-1 rounded-full text-xs bg-green-900/30 text-green-400"

          if (!token.canceled) {
            this.redirectTimeout = setTimeout(() => {
              if (!token.canceled) window.location.href = this.dashboardUrlValue
            }, 1500)
          }
          return
        }
        if (data.status === "failed") {
          this.confirmationBadgeTarget.textContent = "Failed"
          this.confirmationBadgeTarget.className = "inline-block px-2 py-1 rounded-full text-xs bg-red-900/30 text-red-400"
          return
        }
      } catch { /* continue polling */ }
    }
  }

  showStatus(message, type = "info") {
    const el = this.statusTarget
    el.textContent = message
    el.classList.remove("hidden", "bg-red-900/50", "text-red-300", "bg-yellow-900/50", "text-yellow-300", "bg-green-900/50", "text-green-300")
    switch (type) {
      case "error": el.classList.add("bg-red-900/50", "text-red-300"); break
      case "warning": el.classList.add("bg-yellow-900/50", "text-yellow-300"); break
      default: el.classList.add("bg-green-900/50", "text-green-300")
    }
    el.classList.remove("hidden")
  }

  resetSendBtn() {
    this.sendBtnTarget.classList.remove("hidden")
    this.sendBtnTarget.disabled = false
    this.sendBtnTarget.textContent = "Send SOL"
    this.confirmingTarget.classList.add("hidden")
  }
}
