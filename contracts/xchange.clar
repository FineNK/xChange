;; xChange Bridge Contract
;; Handles cross-chain swaps between Bitcoin and Stacks

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u1))
(define-constant ERR_INSUFFICIENT_BALANCE (err u2))
(define-constant ERR_INVALID_SWAP (err u3))

;; Data maps for storing swap information and balances
(define-map balances principal uint)
(define-map pending-swaps 
    { swap-id: uint, 
      initiator: principal,
      amount: uint,
      recipient-btc: (buff 128)
    }
    bool
)

(define-data-var last-swap-id uint u0)

;; Initialize contract
(define-public (initialize)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (ok true)
    )
)

;; Deposit STX tokens into the bridge
(define-public (deposit-stx (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set balances tx-sender 
            (+ (default-to u0 (map-get? balances tx-sender)) amount)
        )
        (ok true)
    )
)

;; Initiate a swap to Bitcoin
(define-public (initiate-swap (amount uint) (recipient-btc (buff 128)))
    (let (
        (sender-balance (default-to u0 (map-get? balances tx-sender)))
        (swap-id (+ (var-get last-swap-id) u1))
    )
        (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_SWAP)
        
        ;; Update sender balance
        (map-set balances tx-sender (- sender-balance amount))
        
        ;; Record the pending swap
        (map-set pending-swaps 
            { swap-id: swap-id,
              initiator: tx-sender,
              amount: amount,
              recipient-btc: recipient-btc
            }
            true
        )
        
        ;; Update last swap ID
        (var-set last-swap-id swap-id)
        (ok swap-id)
    )
)

;; Complete a swap (admin only)
(define-public (complete-swap (swap-id uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-delete pending-swaps 
            { swap-id: swap-id,
              initiator: tx-sender,
              amount: u0,
              recipient-btc: 0x
            }
        )
        (ok true)
    )
)

;; Get pending swap details
(define-read-only (get-pending-swap (swap-id uint))
    (map-get? pending-swaps 
        { swap-id: swap-id,
          initiator: tx-sender,
          amount: u0,
          recipient-btc: 0x
        }
    )
)

;; Get user balance
(define-read-only (get-balance (user principal))
    (default-to u0 (map-get? balances user))
)